// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract ve is IERC721, IERC721Metadata {
    using SafeERC20 for IERC20;

    enum DepositType {
        DEPOSIT_FOR_TYPE,
        CREATE_LOCK_TYPE,
        INCREASE_LOCK_AMOUNT,
        INCREASE_UNLOCK_TIME,
        MERGE_TYPE
    }

    event Deposit(
        address indexed provider,
        uint256 tokenId,
        uint256 value,
        uint256 indexed locktime,
        DepositType deposit_type,
        uint256 ts
    );

    struct Point {
        int128 bias;
        int128 slope; // # -dweight / dt
        uint256 ts;
        uint256 blk; // block
    }

    /**
     * We cannot really do block numbers per se b/c slope is per time, not per block
     * and per block could be fairly bad b/c Ethereum changes blocktimes.
     * What we can do is to extrapolate ***At functions
     */

    struct LockedBalance {
        int128 amount;
        uint256 end;
    }

    event Enter(address indexed user, uint256 vestingInAmount, uint256 mintedAmount);
    event Leave(address indexed user, uint256 vestingOutAmount, uint256 burnedAmount);
    event ShareRevenue(uint256 amount);
    event Withdraw(address indexed provider, uint256 tokenId, uint256 value, uint256 ts);
    event Supply(uint256 prevSupply, uint256 supply);

    uint256 internal constant WEEK = 1 weeks;
    uint256 internal constant MAXTIME = 1 * 365 * 86400;
    int128 internal constant iMAXTIME = 1 * 365 * 86400;
    uint256 internal constant MULTIPLIER = 1 ether;
    address public immutable token;
    uint256 public supply;
    mapping(uint256 => LockedBalance) public locked;

    mapping(uint256 => uint256) public ownership_change;

    uint256 public epoch;
    mapping(uint256 => Point) public point_history; // epoch -> unsigned point
    mapping(uint256 => Point[1_000_000_000]) public user_point_history; // user -> Point[user_epoch]

    mapping(uint256 => uint256) public user_point_epoch;
    mapping(uint256 => int128) public slope_changes; // time -> signed slope change

    mapping(uint256 => uint256) public attachments;
    mapping(uint256 => bool) public voted;
    address public voter;

    string public constant name = "Aera fractal V2";
    string public constant symbol = "aeFRACTALV2";
    string public constant version = "1.0.0";
    uint8 public constant decimals = 18;

    /// @dev Current count of token
    uint256 internal tokenId;

    /// @dev Mapping from NFT ID to the address that owns it.
    mapping(uint256 => address) internal idToOwner;

    /// @dev Mapping from NFT ID to approved address.
    mapping(uint256 => address) internal idToApprovals;

    /// @dev Mapping from owner address to count of his tokens.
    mapping(address => uint256) internal ownerToNFTokenCount;

    /// @dev Mapping from owner address to mapping of index to tokenIds
    mapping(address => mapping(uint256 => uint256)) internal ownerToNFTokenIdList;

    /// @dev Mapping from NFT ID to index of owner
    mapping(uint256 => uint256) internal tokenToOwnerIndex;

    /// @dev Mapping from owner address to mapping of operator addresses.
    mapping(address => mapping(address => bool)) internal ownerToOperators;

    /// @dev Mapping of interface id to bool about whether or not it's supported
    mapping(bytes4 => bool) internal supportedInterfaces;

    /// @dev ERC165 interface ID of ERC165
    bytes4 internal constant ERC165_INTERFACE_ID = 0x01ffc9a7;

    /// @dev ERC165 interface ID of ERC721
    bytes4 internal constant ERC721_INTERFACE_ID = 0x80ac58cd;

    /// @dev ERC165 interface ID of ERC721Metadata
    bytes4 internal constant ERC721_METADATA_INTERFACE_ID = 0x5b5e139f;

    /// @dev reentrancy guard
    uint8 internal constant _not_entered = 1;
    uint8 internal constant _entered = 2;
    uint8 internal _entered_state = 1;
    modifier nonreentrant() {
        require(_entered_state == _not_entered);
        _entered_state = _entered;
        _;
        _entered_state = _not_entered;
    }

    /// @notice Contract constructor
    /// @param token_addr `ERC20CRV` token address
    constructor(address token_addr) {
        token = token_addr;
        voter = msg.sender;
        point_history[0].blk = block.number;
        point_history[0].ts = block.timestamp;

        supportedInterfaces[ERC165_INTERFACE_ID] = true;
        supportedInterfaces[ERC721_INTERFACE_ID] = true;
        supportedInterfaces[ERC721_METADATA_INTERFACE_ID] = true;

        // mint-ish
        emit Transfer(address(0), address(this), tokenId);
        // burn-ish
        emit Transfer(address(this), address(0), tokenId);
    }

    /// @dev Interface identification is specified in ERC-165.
    /// @param _interfaceID Id of the interface
    function supportsInterface(bytes4 _interfaceID) external view returns (bool) {
        return supportedInterfaces[_interfaceID];
    }

    /// @notice Get the most recently recorded rate of voting power decrease for `_tokenId`
    /// @param _tokenId token of the NFT
    /// @return Value of the slope
    function get_last_user_slope(uint256 _tokenId) external view returns (int128) {
        uint256 uepoch = user_point_epoch[_tokenId];
        return user_point_history[_tokenId][uepoch].slope;
    }

    /// @notice Get the timestamp for checkpoint `_idx` for `_tokenId`
    /// @param _tokenId token of the NFT
    /// @param _idx User epoch number
    /// @return Epoch time of the checkpoint
    function user_point_history__ts(uint256 _tokenId, uint256 _idx) external view returns (uint256) {
        return user_point_history[_tokenId][_idx].ts;
    }

    /// @notice Get timestamp when `_tokenId`'s lock finishes
    /// @param _tokenId User NFT
    /// @return Epoch time of the lock end
    function locked__end(uint256 _tokenId) external view returns (uint256) {
        return locked[_tokenId].end;
    }

    function _balance(address _owner) internal view returns (uint256) {
        return ownerToNFTokenCount[_owner];
    }

    function balanceOf(address _owner) external view returns (uint256) {
        return _balance(_owner);
    }

    function ownerOf(uint256 _tokenId) public view returns (address) {
        return idToOwner[_tokenId];
    }

    function getApproved(uint256 _tokenId) external view returns (address) {
        return idToApprovals[_tokenId];
    }

    function isApprovedForAll(address _owner, address _operator) external view returns (bool) {
        return (ownerToOperators[_owner])[_operator];
    }

    function tokenOfOwnerByIndex(address _owner, uint256 _tokenIndex) external view returns (uint256) {
        return ownerToNFTokenIdList[_owner][_tokenIndex];
    }

    function _isApprovedOrOwner(address _spender, uint256 _tokenId) internal view returns (bool) {
        address owner = idToOwner[_tokenId];
        bool spenderIsOwner = owner == _spender;
        bool spenderIsApproved = _spender == idToApprovals[_tokenId];
        bool spenderIsApprovedForAll = (ownerToOperators[owner])[_spender];
        return spenderIsOwner || spenderIsApproved || spenderIsApprovedForAll;
    }

    function isApprovedOrOwner(address _spender, uint256 _tokenId) external view returns (bool) {
        return _isApprovedOrOwner(_spender, _tokenId);
    }

    function _addTokenToOwnerList(address _to, uint256 _tokenId) internal {
        uint256 current_count = _balance(_to);

        ownerToNFTokenIdList[_to][current_count] = _tokenId;
        tokenToOwnerIndex[_tokenId] = current_count;
    }

    function _removeTokenFromOwnerList(address _from, uint256 _tokenId) internal {
        // Delete
        uint256 current_count = _balance(_from) - 1;
        uint256 current_index = tokenToOwnerIndex[_tokenId];

        if (current_count == current_index) {
            // update ownerToNFTokenIdList
            ownerToNFTokenIdList[_from][current_count] = 0;
            // update tokenToOwnerIndex
            tokenToOwnerIndex[_tokenId] = 0;
        } else {
            uint256 lastTokenId = ownerToNFTokenIdList[_from][current_count];

            // Add
            // update ownerToNFTokenIdList
            ownerToNFTokenIdList[_from][current_index] = lastTokenId;
            // update tokenToOwnerIndex
            tokenToOwnerIndex[lastTokenId] = current_index;

            // Delete
            // update ownerToNFTokenIdList
            ownerToNFTokenIdList[_from][current_count] = 0;
            // update tokenToOwnerIndex
            tokenToOwnerIndex[_tokenId] = 0;
        }
    }

    function _addTokenTo(address _to, uint256 _tokenId) internal {
        // Throws if `_tokenId` is owned by someone
        assert(idToOwner[_tokenId] == address(0));
        // Change the owner
        idToOwner[_tokenId] = _to;
        // Update owner token index tracking
        _addTokenToOwnerList(_to, _tokenId);
        // Change count tracking
        ownerToNFTokenCount[_to] += 1;
    }

    function _removeTokenFrom(address _from, uint256 _tokenId) internal {
        // Throws if `_from` is not the current owner
        assert(idToOwner[_tokenId] == _from);
        // Change the owner
        idToOwner[_tokenId] = address(0);
        // Update owner token index tracking
        _removeTokenFromOwnerList(_from, _tokenId);
        // Change count tracking
        ownerToNFTokenCount[_from] -= 1;
    }

    function _clearApproval(address _owner, uint256 _tokenId) internal {
        // Throws if `_owner` is not the current owner
        assert(idToOwner[_tokenId] == _owner);
        if (idToApprovals[_tokenId] != address(0)) {
            // Reset approvals
            idToApprovals[_tokenId] = address(0);
        }
    }

    function _transferFrom(
        address _from,
        address _to,
        uint256 _tokenId,
        address _sender
    ) internal {
        require(attachments[_tokenId] == 0 && !voted[_tokenId], "attached");
        // Check requirements
        require(_isApprovedOrOwner(_sender, _tokenId));
        // Clear approval. Throws if `_from` is not the current owner
        _clearApproval(_from, _tokenId);
        // Remove NFT. Throws if `_tokenId` is not a valid NFT
        _removeTokenFrom(_from, _tokenId);
        // Add NFT
        _addTokenTo(_to, _tokenId);
        // Set the block of ownership transfer (for Flash NFT protection)
        ownership_change[_tokenId] = block.number;
        // Log the transfer
        emit Transfer(_from, _to, _tokenId);
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) external {
        _transferFrom(_from, _to, _tokenId, msg.sender);
    }

    function _isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId,
        bytes memory _data
    ) public {
        _transferFrom(_from, _to, _tokenId, msg.sender);

        if (_isContract(_to)) {
            // Throws if transfer destination is a contract which does not implement 'onERC721Received'
            try IERC721Receiver(_to).onERC721Received(msg.sender, _from, _tokenId, _data) returns (bytes4) {} catch (
                bytes memory reason
            ) {
                if (reason.length == 0) {
                    revert("ERC721: transfer to non ERC721Receiver implementer");
                } else {
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        }
    }

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) external {
        safeTransferFrom(_from, _to, _tokenId, "");
    }

    function approve(address _approved, uint256 _tokenId) public {
        address owner = idToOwner[_tokenId];
        // Throws if `_tokenId` is not a valid NFT
        require(owner != address(0));
        // Throws if `_approved` is the current owner
        require(_approved != owner);
        // Check requirements
        bool senderIsOwner = (idToOwner[_tokenId] == msg.sender);
        bool senderIsApprovedForAll = (ownerToOperators[owner])[msg.sender];
        require(senderIsOwner || senderIsApprovedForAll);
        // Set the approval
        idToApprovals[_tokenId] = _approved;
        emit Approval(owner, _approved, _tokenId);
    }

    function setApprovalForAll(address _operator, bool _approved) external {
        // Throws if `_operator` is the `msg.sender`
        assert(_operator != msg.sender);
        ownerToOperators[msg.sender][_operator] = _approved;
        emit ApprovalForAll(msg.sender, _operator, _approved);
    }

    function _mint(address _to, uint256 _tokenId) internal returns (bool) {
        // Throws if `_to` is zero address
        assert(_to != address(0));
        // Add NFT. Throws if `_tokenId` is owned by someone
        _addTokenTo(_to, _tokenId);
        emit Transfer(address(0), _to, _tokenId);
        return true;
    }

    function _checkpoint(
        uint256 _tokenId,
        LockedBalance memory old_locked,
        LockedBalance memory new_locked
    ) internal {
        Point memory u_old;
        Point memory u_new;
        int128 old_dslope = 0;
        int128 new_dslope = 0;
        uint256 _epoch = epoch;

        if (_tokenId != 0) {
            // Calculate slopes and biases
            // Kept at zero when they have to
            if (old_locked.end > block.timestamp && old_locked.amount > 0) {
                u_old.slope = old_locked.amount / iMAXTIME;
                u_old.bias = u_old.slope * int128(int256(old_locked.end - block.timestamp));
            }
            if (new_locked.end > block.timestamp && new_locked.amount > 0) {
                u_new.slope = new_locked.amount / iMAXTIME;
                u_new.bias = u_new.slope * int128(int256(new_locked.end - block.timestamp));
            }

            // Read values of scheduled changes in the slope
            // old_locked.end can be in the past and in the future
            // new_locked.end can ONLY by in the FUTURE unless everything expired: than zeros
            old_dslope = slope_changes[old_locked.end];
            if (new_locked.end != 0) {
                if (new_locked.end == old_locked.end) {
                    new_dslope = old_dslope;
                } else {
                    new_dslope = slope_changes[new_locked.end];
                }
            }
        }

        Point memory last_point = Point({ bias: 0, slope: 0, ts: block.timestamp, blk: block.number });
        if (_epoch > 0) {
            last_point = point_history[_epoch];
        }
        uint256 last_checkpoint = last_point.ts;
        // initial_last_point is used for extrapolation to calculate block number
        // (approximately, for *At methods) and save them
        // as we cannot figure that out exactly from inside the contract
        Point memory initial_last_point = last_point;
        uint256 block_slope = 0; // dblock/dt
        if (block.timestamp > last_point.ts) {
            block_slope = (MULTIPLIER * (block.number - last_point.blk)) / (block.timestamp - last_point.ts);
        }
        // If last point is already recorded in this block, slope=0
        // But that's ok b/c we know the block in such case

        // Go over weeks to fill history and calculate what the current point is
        {
            uint256 t_i = (last_checkpoint / WEEK) * WEEK;
            for (uint256 i = 0; i < 255; ++i) {
                // Hopefully it won't happen that this won't get used in 5 years!
                // If it does, users will be able to withdraw but vote weight will be broken
                t_i += WEEK;
                int128 d_slope = 0;
                if (t_i > block.timestamp) {
                    t_i = block.timestamp;
                } else {
                    d_slope = slope_changes[t_i];
                }
                last_point.bias -= last_point.slope * int128(int256(t_i - last_checkpoint));
                last_point.slope += d_slope;
                if (last_point.bias < 0) {
                    // This can happen
                    last_point.bias = 0;
                }
                if (last_point.slope < 0) {
                    // This cannot happen - just in case
                    last_point.slope = 0;
                }
                last_checkpoint = t_i;
                last_point.ts = t_i;
                last_point.blk = initial_last_point.blk + (block_slope * (t_i - initial_last_point.ts)) / MULTIPLIER;
                _epoch += 1;
                if (t_i == block.timestamp) {
                    last_point.blk = block.number;
                    break;
                } else {
                    point_history[_epoch] = last_point;
                }
            }
        }

        epoch = _epoch;
        // Now point_history is filled until t=now

        if (_tokenId != 0) {
            // If last point was in this block, the slope change has been applied already
            // But in such case we have 0 slope(s)
            last_point.slope += (u_new.slope - u_old.slope);
            last_point.bias += (u_new.bias - u_old.bias);
            if (last_point.slope < 0) {
                last_point.slope = 0;
            }
            if (last_point.bias < 0) {
                last_point.bias = 0;
            }
        }

        // Record the changed point into history
        point_history[_epoch] = last_point;

        if (_tokenId != 0) {
            // Schedule the slope changes (slope is going down)
            // We subtract new_user_slope from [new_locked.end]
            // and add old_user_slope to [old_locked.end]
            if (old_locked.end > block.timestamp) {
                // old_dslope was <something> - u_old.slope, so we cancel that
                old_dslope += u_old.slope;
                if (new_locked.end == old_locked.end) {
                    old_dslope -= u_new.slope; // It was a new deposit, not extension
                }
                slope_changes[old_locked.end] = old_dslope;
            }

            if (new_locked.end > block.timestamp) {
                if (new_locked.end > old_locked.end) {
                    new_dslope -= u_new.slope; // old slope disappeared at this point
                    slope_changes[new_locked.end] = new_dslope;
                }
                // else: we recorded it already in old_dslope
            }
            // Now handle user history
            uint256 user_epoch = user_point_epoch[_tokenId] + 1;

            user_point_epoch[_tokenId] = user_epoch;
            u_new.ts = block.timestamp;
            u_new.blk = block.number;
            user_point_history[_tokenId][user_epoch] = u_new;
        }
    }

    function _deposit_for(
        uint256 _tokenId,
        uint256 _value,
        LockedBalance memory locked_balance,
        DepositType deposit_type
    ) internal {
        LockedBalance memory _locked = locked_balance;
        uint256 supply_before = supply;

        supply = supply_before + _value;
        LockedBalance memory old_locked;
        (old_locked.amount, old_locked.end) = (_locked.amount, _locked.end);
        // Adding to existing lock, or if a lock is expired - creating a new one
        _locked.amount += int128(int256(_value));
        locked[_tokenId] = _locked;

        // Possibilities:
        // Both old_locked.end could be current or expired (>/< block.timestamp)
        // value == 0 (extend lock) or value > 0 (add to lock or extend lock)
        // _locked.end > block.timestamp (always)
        _checkpoint(_tokenId, old_locked, _locked);

        address from = msg.sender;
        if (_value != 0 && deposit_type != DepositType.MERGE_TYPE) {
            assert(IERC20(token).transferFrom(from, address(this), _value));
        }

        emit Deposit(from, _tokenId, _value, _locked.end, deposit_type, block.timestamp);
        emit Supply(supply_before, supply_before + _value);
    }

    function block_number() external view returns (uint256) {
        return block.number;
    }

    function checkpoint() external {
        _checkpoint(0, LockedBalance(0, 0), LockedBalance(0, 0));
    }

    function _create_lock(
        uint256 _value,
        address _to
    ) internal returns (uint256) {
        uint256 totalLockedTokenSupply = IERC20(token).balanceOf(address(this));
        uint256 totalFreshBeets = totalSupply();
        uint256 mintAmount;
        // If no fBeets exists, mint it 1:1 to the amount put in
        if (totalFreshBeets == 0 || totalLockedTokenSupply == 0) {
            mintAmount = _value;
        }
        // Calculate and mint the amount of fBeets the blp is worth. The ratio will change overtime
        else {
            uint256 shareOfFreshBeets = (_value * totalFreshBeets) / totalLockedTokenSupply;

            mintAmount = shareOfFreshBeets;
        }

        require(_value > 0); // dev: need non-zero value

        ++tokenId;
        uint256 _tokenId = tokenId;
        _mint(_to, _tokenId);

        _deposit_for(_tokenId, _value, locked[_tokenId], DepositType.CREATE_LOCK_TYPE);

        emit Enter(msg.sender, _value, mintAmount);

        return _tokenId;
    }

    function create_lock(uint256 _value) external nonreentrant returns (uint256) {
        return _create_lock(_value, msg.sender);
    }

    function _find_block_epoch(uint256 _block, uint256 max_epoch) internal view returns (uint256) {
        // Binary search
        uint256 _min = 0;
        uint256 _max = max_epoch;
        for (uint256 i = 0; i < 128; ++i) {
            // Will be always enough for 128-bit numbers
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 1) / 2;
            if (point_history[_mid].blk <= _block) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }
        return _min;
    }

    function _balanceOfNFT(uint256 _tokenId, uint256 _t) internal view returns (uint256) {
        uint256 _epoch = user_point_epoch[_tokenId];
        if (_epoch == 0) {
            return 0;
        } else {
            Point memory last_point = user_point_history[_tokenId][_epoch];
            last_point.bias -= last_point.slope * int128(int256(_t) - int256(last_point.ts));
            if (last_point.bias < 0) {
                last_point.bias = 0;
            }
            return uint256(int256(last_point.bias));
        }
    }

    function tokenURI(uint256 _tokenId) external view returns (string memory) {
        require(idToOwner[_tokenId] != address(0), "Query for nonexistent token");
        LockedBalance memory _locked = locked[_tokenId];
        return
            _tokenURI(_tokenId, _balanceOfNFT(_tokenId, block.timestamp), _locked.end, uint256(int256(_locked.amount)));
    }

    function balanceOfNFT(uint256 _tokenId) external view returns (uint256) {
        if (ownership_change[_tokenId] == block.number) return 0;
        return _balanceOfNFT(_tokenId, block.timestamp);
    }

    function balanceOfNFTAt(uint256 _tokenId, uint256 _t) external view returns (uint256) {
        return _balanceOfNFT(_tokenId, _t);
    }

    function _balanceOfAtNFT(uint256 _tokenId, uint256 _block) internal view returns (uint256) {
        // Copying and pasting totalSupply code because Vyper cannot pass by
        // reference yet
        assert(_block <= block.number);

        // Binary search
        uint256 _min = 0;
        uint256 _max = user_point_epoch[_tokenId];
        for (uint256 i = 0; i < 128; ++i) {
            // Will be always enough for 128-bit numbers
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 1) / 2;
            if (user_point_history[_tokenId][_mid].blk <= _block) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }

        Point memory upoint = user_point_history[_tokenId][_min];

        uint256 max_epoch = epoch;
        uint256 _epoch = _find_block_epoch(_block, max_epoch);
        Point memory point_0 = point_history[_epoch];
        uint256 d_block = 0;
        uint256 d_t = 0;
        if (_epoch < max_epoch) {
            Point memory point_1 = point_history[_epoch + 1];
            d_block = point_1.blk - point_0.blk;
            d_t = point_1.ts - point_0.ts;
        } else {
            d_block = block.number - point_0.blk;
            d_t = block.timestamp - point_0.ts;
        }
        uint256 block_time = point_0.ts;
        if (d_block != 0) {
            block_time += (d_t * (_block - point_0.blk)) / d_block;
        }

        upoint.bias -= upoint.slope * int128(int256(block_time - upoint.ts));
        if (upoint.bias >= 0) {
            return uint256(uint128(upoint.bias));
        } else {
            return 0;
        }
    }

    function balanceOfAtNFT(uint256 _tokenId, uint256 _block) external view returns (uint256) {
        return _balanceOfAtNFT(_tokenId, _block);
    }

    function _supply_at(Point memory point, uint256 t) internal view returns (uint256) {
        Point memory last_point = point;
        uint256 t_i = (last_point.ts / WEEK) * WEEK;
        for (uint256 i = 0; i < 255; ++i) {
            t_i += WEEK;
            int128 d_slope = 0;
            if (t_i > t) {
                t_i = t;
            } else {
                d_slope = slope_changes[t_i];
            }
            last_point.bias -= last_point.slope * int128(int256(t_i - last_point.ts));
            if (t_i == t) {
                break;
            }
            last_point.slope += d_slope;
            last_point.ts = t_i;
        }

        if (last_point.bias < 0) {
            last_point.bias = 0;
        }
        return uint256(uint128(last_point.bias));
    }

    function totalSupplyAtT(uint256 t) public view returns (uint256) {
        uint256 _epoch = epoch;
        Point memory last_point = point_history[_epoch];
        return _supply_at(last_point, t);
    }

    function totalSupply() public view returns (uint256) {
        return totalSupplyAtT(block.timestamp);
    }

    function totalSupplyAt(uint256 _block) external view returns (uint256) {
        assert(_block <= block.number);
        uint256 _epoch = epoch;
        uint256 target_epoch = _find_block_epoch(_block, _epoch);

        Point memory point = point_history[target_epoch];
        uint256 dt = 0;
        if (target_epoch < _epoch) {
            Point memory point_next = point_history[target_epoch + 1];
            if (point.blk != point_next.blk) {
                dt = ((_block - point.blk) * (point_next.ts - point.ts)) / (point_next.blk - point.blk);
            }
        } else {
            if (point.blk != block.number) {
                dt = ((_block - point.blk) * (block.timestamp - point.ts)) / (block.number - point.blk);
            }
        }
        // Now dt contains info on how far are we beyond point
        return _supply_at(point, point.ts + dt);
    }

    function locking(uint256 _tokenId) external view returns (int256) {
        LockedBalance memory _locked = locked[_tokenId];

        return _locked.amount;
    }

    function _tokenURI(
        uint256 _tokenId,
        uint256 _balanceOf,
        uint256 _locked_end,
        uint256 _value
    ) internal pure returns (string memory output) {
        output = '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350"><style>.base { fill: white; font-family: serif; font-size: 14px; }</style><rect width="100%" height="100%" fill="black" /><text x="10" y="20" class="base">';
        output = string(
            abi.encodePacked(output, "token ", toString(_tokenId), '</text><text x="10" y="40" class="base">')
        );
        output = string(
            abi.encodePacked(output, "balanceOf ", toString(_balanceOf), '</text><text x="10" y="60" class="base">')
        );
        output = string(
            abi.encodePacked(output, "locked_end ", toString(_locked_end), '</text><text x="10" y="80" class="base">')
        );
        output = string(abi.encodePacked(output, "value ", toString(_value), "</text></svg>"));

        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "lock #',
                        toString(_tokenId),
                        '", "description": "Solidly locks, can be used to boost gauge yields, vote on token emission, and receive bribes", "image": "data:image/svg+xml;base64,',
                        Base64.encode(bytes(output)),
                        '"}'
                    )
                )
            )
        );
        output = string(abi.encodePacked("data:application/json;base64,", json));
    }

    function toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT license
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function _burn(uint256 _tokenId) internal {
        require(_isApprovedOrOwner(msg.sender, _tokenId), "caller is not owner nor approved");

        address owner = ownerOf(_tokenId);

        // Clear approval
        approve(address(0), _tokenId);
        // Remove token
        _removeTokenFrom(msg.sender, _tokenId);
        emit Transfer(owner, address(0), _tokenId);
    }
}

contract AeraEmissionDistributor is AccessControl, Ownable {
    using SafeERC20 for IERC20;

    // TokenInfo Struct
    struct TokenInfo {
        address user; // address from the owner of this aeFractalV2
        uint256 numberNFT; // TokenId aeFractalV2
    }

    /******************** AnotherToken Structs **********************/
    struct PoolInfoAnotherToken {
        address tokenReward; // address from the Reward of this each Pool
        uint256 anotherTokenPerBlock; // How much AnotherTokens Per Block
        bool isClosed; // If this pool reward isClosed or not
        uint256 allocPoint; // How many allocation points assigned to this pool. the fraction AnotherToken to distribute per block.
        uint256 lastRewardBlock; // Last block number that AnotherToken distribution occurs.
        uint256 accAnotherTokenPerShare; // Accumulated AERA per aeFractalV2. this is multiplied by ACC_ANOTHERTOKEN_PRECISION for more exact results (rounding errors)
    }

    struct UserInfoAnotherToken {
        uint256 amount; // How many AERA locked by the user on veAERA.
        uint256 rewardDebt; // AnotherToken Reward debt.
    }
    /****************************************************************/

    PoolInfoAnotherToken[] public poolInfoAnotherToken; // an array to store information of all pools of another token
    uint256 public totalPidsAnotherToken = 0; // total number of another token pools
    mapping(uint256 => mapping(address => mapping(uint256 => UserInfoAnotherToken))) public userInfoAnotherToken; // mapping form poolId => user Address => User Info

    TokenInfo[] public tokenInfo; // mapping form poolId => user Address => User Info

    uint256 public totalAnotherAllocPoint = 0;

    mapping(address => uint256[]) public tokenIdsByUser;

    mapping(address => uint256) public totalNftsByUser;

    uint256 private constant ACC_ANOTHERTOKEN_PRECISION = 1e12; // precision used for calculations involving another token
    uint256 public constant POOL_PERCENTAGE = 0.876e3; // Percentage of AERA allocated to pools

    uint256 public constant DENOMINATOR = 1e3; // Constant denominator for calculating allocation points

    IERC721 public aeFractalV2; // aeFractalV2 ERC721 token

    /* AnotherToken Rewards Events*/
    event LogSetPoolAnotherToken(
        uint256 indexed pid,
        address indexed tokenReward,
        bool indexed isClosed,
        uint256 allocPoint
    );
    event LogPoolAnotherTokenAddition(
        uint256 indexed pid,
        address indexed tokenReward,
        bool indexed isClosed,
        uint256 allocPoint
    );
    event DepositAnotherToken(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event WithdrawAnotherToken(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event HarvestAnotherToken(address indexed user, uint256 indexed pid, uint256 amount);
    event LogUpdatePoolAnotherToken(
        uint256 indexed pid,
        uint256 lastRewardBlock,
        uint256 totalAmountLockedAera,
        uint256 accAERAPerShare
    );

    /* General Events */
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        IERC721 _aeFractalV2 // aeFractalV2 ERC721 token
    ) {
        require(address(_aeFractalV2) != address(0), "invalid aeFractalV2's address");
        aeFractalV2 = _aeFractalV2;
    }

    // Function to deposit veAERA token to the contract and receive rewards
    function depositToChef(uint256 _pid, uint256 _tokenId) external {
        // Check if msg.sender is the owner of the veAERA
        address ownerOfTokenId = IERC721(aeFractalV2).ownerOf(_tokenId);
        require(ownerOfTokenId == msg.sender, "You are not the owner of this veAERA");

        // AnotherToken Rewards attributes
        PoolInfoAnotherToken memory poolAnotherToken = updatePoolAnotherToken(_pid);
        UserInfoAnotherToken storage userAnotherToken = userInfoAnotherToken[_pid][msg.sender][_tokenId];

        totalNftsByUser[msg.sender] = totalNftsByUser[msg.sender] + 1;
        tokenIdsByUser[msg.sender].push(_tokenId);

        // Transfer the veAERA token from the user to the contract
        ve(address(aeFractalV2)).transferFrom(msg.sender, address(this), _tokenId);
        uint256 amount = uint256(ve(address(aeFractalV2)).locking(_tokenId));

        /******************** AnotherToken Rewards Code ********************/
        // AnotherToken Rewards Code
        if (!poolAnotherToken.isClosed) {
            userAnotherToken.amount = userAnotherToken.amount + amount;
            userAnotherToken.rewardDebt =
                userAnotherToken.rewardDebt +
                (amount * poolAnotherToken.accAnotherTokenPerShare) /
                ACC_ANOTHERTOKEN_PRECISION;
        }
        /*******************************************************************/

        // Push the tokenInfo to the tokenInfo array
        tokenInfo.push(TokenInfo({ user: msg.sender, numberNFT: _tokenId }));

        // Events
        // Emit events for deposit
        emit DepositAnotherToken(msg.sender, _pid, amount, msg.sender);
    }

    function depositAnotherToken(uint256 _pid, uint256 _amount) external onlyOwner {
        require(_pid < totalPidsAnotherToken, "invalid pool id");
        PoolInfoAnotherToken storage poolAnotherToken = poolInfoAnotherToken[_pid];
        if (!poolAnotherToken.isClosed) {
            IERC20(poolAnotherToken.tokenReward).transferFrom(msg.sender, address(this), _amount);
        }
    }

    function withdrawAndDistribute(uint256 _pid, uint256 _tokenId) external {

        // AnotherToken Rewards attributes
        PoolInfoAnotherToken memory poolAnotherToken = updatePoolAnotherToken(_pid);
        UserInfoAnotherToken storage userAnotherToken = userInfoAnotherToken[_pid][msg.sender][_tokenId];

        uint256 amount = uint256(ve(address(aeFractalV2)).locking(_tokenId)); // amount of locked AERA on that veAERA

        /******************** AnotherToken Rewards Code ********************/
        if (!poolAnotherToken.isClosed) {
            // this would  be the amount if the user joined right from the start of the farm
            uint256 accumulatedWAnotherToken = (userAnotherToken.amount * poolAnotherToken.accAnotherTokenPerShare) /
                ACC_ANOTHERTOKEN_PRECISION;
            // subtracting the rewards the user is not eligible for
            uint256 eligibleAnotherToken = accumulatedWAnotherToken - userAnotherToken.rewardDebt;
            userAnotherToken.amount = userAnotherToken.amount - amount; // put user amount of UserInfo a zero
            userAnotherToken.rewardDebt =
                (userAnotherToken.amount * poolAnotherToken.accAnotherTokenPerShare) /
                ACC_ANOTHERTOKEN_PRECISION; // update AnotherToken Reward Debt
            safeAnotherTokenTransfer(_pid, msg.sender, eligibleAnotherToken);
        }
        /********************************************************************/

        IERC721(aeFractalV2).safeTransferFrom(address(this), msg.sender, _tokenId); // transfer veAERA to his owner

        uint256[] storage tokenIdsByCaller = tokenIdsByUser[msg.sender];
        for (uint256 i = 0; i < tokenIdsByCaller.length; ) {
            if (tokenIdsByCaller[i] == _tokenId) {
                delete tokenIdsByCaller[i];
                break;
            }
            unchecked {
                ++i;
            }
        }

        totalNftsByUser[msg.sender] = totalNftsByUser[msg.sender] - 1;

        // Events
        emit WithdrawAnotherToken(msg.sender, _pid, amount, msg.sender);
    }

    function harvestAndDistributeAnotherToken(uint256 _pid, uint256 _tokenId) public {
        // Get the current pool information for the specified pid
        PoolInfoAnotherToken memory poolAnotherToken = updatePoolAnotherToken(_pid);
        // Get the current user's information for the specified pid and tokenId
        UserInfoAnotherToken storage userAnotherToken = userInfoAnotherToken[_pid][msg.sender][_tokenId];

        if (!poolAnotherToken.isClosed) {
            // Calculate the total accumulated AnotherToken rewards for the user based on their LP token amount
            uint256 accumulatedAnotherToken = (userAnotherToken.amount * poolAnotherToken.accAnotherTokenPerShare) /
                ACC_ANOTHERTOKEN_PRECISION;
            // Subtract any rewards the user is not eligible for
            uint256 eligibleAnotherToken = accumulatedAnotherToken - userAnotherToken.rewardDebt;

            // Update the user's reward debt to the current accumulated AnotherToken rewards
            userAnotherToken.rewardDebt = accumulatedAnotherToken;

            // If there are any eligible AnotherToken rewards, transfer them to the user
            if (eligibleAnotherToken > 0) {
                safeAnotherTokenTransfer(_pid, msg.sender, eligibleAnotherToken);
            }

            // Emit an event to log the harvest
            emit HarvestAnotherToken(msg.sender, _pid, eligibleAnotherToken);
        }
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid, uint256 _tokenId) public {
        // Get the current user's information for the specified pid and tokenId
        UserInfoAnotherToken storage userAnotherToken = userInfoAnotherToken[_pid][msg.sender][_tokenId];
        // Get the current user's LP token amount
        userAnotherToken.amount = 0;
        userAnotherToken.rewardDebt = 0;
        // Transfer the user's LP token back to them using the IERC721 contract
        IERC721(aeFractalV2).safeTransferFrom(address(this), msg.sender, _tokenId);

        uint256[] memory tokenIdsByCaller = tokenIdsByUser[msg.sender];
        for (uint256 i = 0; i < tokenIdsByCaller.length; ) {
            if (tokenIdsByCaller[i] == _tokenId) {
                delete tokenIdsByCaller[i];
                break;
            }
            unchecked {
                ++i;
            }
        }

        totalNftsByUser[msg.sender] = totalNftsByUser[msg.sender] - 1;
    }

    // Add a new AnotherToken to the pool. Can only be called by the owner.
    function addAnotherToken(
        address _tokenReward,
        uint256 _anotherTokenPerBlock,
        bool _isClosed,
        uint256 _allocPoint
    ) public onlyOwner {
        // Add a new pool with the specified token reward, block reward, closed status, allocation point and current timestamp to the poolInfoAnotherToken array
        poolInfoAnotherToken.push(
            PoolInfoAnotherToken({
                tokenReward: _tokenReward,
                anotherTokenPerBlock: _anotherTokenPerBlock,
                isClosed: _isClosed,
                allocPoint: _allocPoint,
                lastRewardBlock: block.number,
                accAnotherTokenPerShare: 0
            })
        );

        totalPidsAnotherToken++;
        totalAnotherAllocPoint = totalAnotherAllocPoint + _allocPoint;
        // Emit an event to log the pool addition
        emit LogPoolAnotherTokenAddition(totalPidsAnotherToken - 1, _tokenReward, _isClosed, _allocPoint);
    }

    // Update the given Another Token pool's. Can only be called by the owner.
    function setAnotherToken(
        uint256 _pid,
        address _tokenReward,
        uint256 _allocPoint,
        uint256 _anotherTokenPerBlock,
        bool _isClosed
    ) public onlyOwner {
        // Update the allocation point, token reward, block reward and closed status of the specified AnotherToken pool
        PoolInfoAnotherToken storage poolAnotherToken = poolInfoAnotherToken[_pid];
        poolAnotherToken.allocPoint = _allocPoint;
        poolAnotherToken.tokenReward = _tokenReward;
        poolAnotherToken.anotherTokenPerBlock = _anotherTokenPerBlock;
        poolAnotherToken.isClosed = _isClosed;
        // Emit an event to log the pool update
        emit LogSetPoolAnotherToken(_pid, _tokenReward, _isClosed, _allocPoint);
    }

    // View function to see the pending AnotherToken rewards for a user
    function pendingAnotherToken(
        uint256 _pid,
        uint256 _tokenId,
        address _user
    ) external view returns (uint256 pending) {
        PoolInfoAnotherToken storage poolAnotherToken = poolInfoAnotherToken[_pid];
        UserInfoAnotherToken storage userAnotherToken = userInfoAnotherToken[_pid][_user][_tokenId];
        // Get the accumulated AnotherToken per LP token
        uint256 accAnotherTokenPerShare = poolAnotherToken.accAnotherTokenPerShare;
        // Calculate the pending AnotherToken rewards for the user based on their staked LP tokens and
        // subtracting any rewards they are not eligible for or have already claimed
        uint256 anotherTokenSupply = IERC20(poolInfoAnotherToken[_pid].tokenReward).balanceOf(address(this));

        if (block.number > poolAnotherToken.lastRewardBlock && anotherTokenSupply > 0) {
            uint256 blocksSinceLastReward = block.number - poolAnotherToken.lastRewardBlock;
            // based on the pool weight (allocation points) we calculate the anotherToken rewarded for this specific pool
            uint256 anotherTokenRewards = (blocksSinceLastReward +
                poolAnotherToken.anotherTokenPerBlock *
                poolAnotherToken.allocPoint) / totalAnotherAllocPoint;
            // we take parts of the rewards for treasury, these can be subject to change, so we recalculate it a value of 1000 = 100%
            uint256 anotherTokenRewardsForPool = (anotherTokenRewards * DENOMINATOR) / DENOMINATOR;

            // we calculate the new amount of accumulated anotherToken per veAERA
            accAnotherTokenPerShare =
                accAnotherTokenPerShare +
                ((anotherTokenRewardsForPool * ACC_ANOTHERTOKEN_PRECISION) / anotherTokenSupply);
        }
        // Calculate the pending AnotherToken rewards for the user based on their staked LP tokens and subtracting any rewards they are not eligible for or have already claimed
        pending =
            (userAnotherToken.amount * accAnotherTokenPerShare) /
            ACC_ANOTHERTOKEN_PRECISION -
            userAnotherToken.rewardDebt;
    }

    // Update reward variables of the given anotherToken pool to be up-to-date.
    function updatePoolAnotherToken(uint256 _pid) public returns (PoolInfoAnotherToken memory poolAnotherToken) {
        poolAnotherToken = poolInfoAnotherToken[_pid];

        if (block.number > poolAnotherToken.lastRewardBlock) {
            // total of AnotherTokens staked for this pool
            uint256 anotherTokenSupply = IERC20(poolInfoAnotherToken[_pid].tokenReward).balanceOf(address(this));
            if (anotherTokenSupply > 0) {
                uint256 blocksSinceLastReward = block.number - poolAnotherToken.lastRewardBlock;

                // rewards for this pool based on his allocation points
                uint256 anotherTokenRewards = (blocksSinceLastReward *
                    poolAnotherToken.anotherTokenPerBlock *
                    poolAnotherToken.allocPoint) / totalAnotherAllocPoint;

                uint256 anotherTokenRewardsForPool = (anotherTokenRewards * DENOMINATOR) / DENOMINATOR;

                poolAnotherToken.accAnotherTokenPerShare =
                    poolAnotherToken.accAnotherTokenPerShare +
                    ((anotherTokenRewardsForPool * ACC_ANOTHERTOKEN_PRECISION) / anotherTokenSupply);
            }
            poolAnotherToken.lastRewardBlock = block.number;
            poolInfoAnotherToken[_pid] = poolAnotherToken;

            /*emit LogUpdatePool(_pid, poolAnotherToken.lastRewardBlock, anotherTokenSupply, poolAnotherToken.accAnotherTokenPerShare);*/
        }
    }

    // Safe anotherToken transfer function, just in case if rounding error causes pool to not have enough anotherToken.
    function safeAnotherTokenTransfer(
        uint256 _pid,
        address _to,
        uint256 _amount
    ) internal {
        // Get the specified anotherToken pool
        PoolInfoAnotherToken memory pool = poolInfoAnotherToken[_pid];
        // Check the balance of anotherToken in the pool
        uint256 anotherTokenBalance = IERC20(pool.tokenReward).balanceOf(address(this));
        // If the requested amount is more than the balance, transfer the entire balance
        if (_amount > anotherTokenBalance) {
            IERC20(pool.tokenReward).transfer(_to, anotherTokenBalance);
        } else {
            // Otherwise, transfer the requested amount
            IERC20(pool.tokenReward).transfer(_to, _amount);
        }
    }
}
