// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract ve is IERC721, IERC721Metadata, Ownable {
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
        uint tokenId,
        uint value,
        uint indexed locktime,
        DepositType deposit_type,
        uint ts
    );

    struct Point {
        int128 bias;
        int128 slope; // # -dweight / dt
        uint256 ts;
        uint256 blk; // block
    }

    struct LockedBalance {
        int128 amount;
        uint256 end;
    }

    event Withdraw(address indexed provider, uint tokenId, uint value, uint ts);
    event Supply(uint prevSupply, uint supply);

    uint internal constant WEEK = 1 weeks;
    uint internal constant MULTIPLIER = 1 ether;

    address public immutable token;
    uint public supply;
    mapping(uint => LockedBalance) public locked;

    mapping(uint => uint) public ownership_change;

    uint public epoch;
    mapping(uint => Point) public point_history; // epoch -> unsigned point
    mapping(uint => Point[1000000000]) public token_point_history; // tokenId -> Point[token_epoch]

    mapping(uint => uint) public token_point_epoch;
    mapping(uint => int128) public slope_changes; // time -> signed slope change

    mapping(uint => uint) public attachments;
    mapping(uint => bool) public voted;
    address public voter;

    string public constant name = "araFractalV2";
    string public constant symbol = "araFractal";
    string public constant version = "1.0.0";
    uint8 public constant decimals = 18;

    /// @dev Current count of token
    uint internal tokenId;

    uint256 public amountTobeLocked;

    /// @dev Mapping from NFT ID to the address that owns it.
    mapping(uint => address) internal idToOwner;

    /// @dev Mapping from NFT ID to approved address.
    mapping(uint => address) internal idToApprovals;

    /// @dev Mapping from owner address to count of his tokens.
    mapping(address => uint) internal ownerToNFTokenCount;

    /// @dev Mapping from owner address to mapping of index to tokenIds
    mapping(address => mapping(uint => uint)) internal ownerToNFTokenIdList;

    /// @dev Mapping from NFT ID to index of owner
    mapping(uint => uint) internal tokenToOwnerIndex;

    /// @dev Mapping from owner address to mapping of operator addresses.
    mapping(address => mapping(address => bool)) internal ownerToOperators;

    /// @dev Mapping of interface id to bool about whether or not it's supported
    mapping(bytes4 => bool) internal supportedInterfaces;

    uint256 public tSupply;

    /// @dev ERC165 interface ID of ERC165
    bytes4 internal constant ERC165_INTERFACE_ID = 0x01ffc9a7;

    /// @dev ERC165 interface ID of ERC721
    bytes4 internal constant ERC721_INTERFACE_ID = 0x80ac58cd;

    /// @dev ERC165 interface ID of ERC721Metadata
    bytes4 internal constant ERC721_METADATA_INTERFACE_ID = 0x5b5e139f;

    bool public canCreateFractals;

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
    constructor(
        address token_addr,
        uint256 _amountTobeLocked,
        bool _canCreateFractals
    ) {
        token = token_addr;
        voter = msg.sender;
        point_history[0].blk = block.number;
        point_history[0].ts = block.timestamp;

        supportedInterfaces[ERC165_INTERFACE_ID] = true;
        supportedInterfaces[ERC721_INTERFACE_ID] = true;
        supportedInterfaces[ERC721_METADATA_INTERFACE_ID] = true;

        amountTobeLocked = _amountTobeLocked;

        canCreateFractals = _canCreateFractals;
        // mint-ish
        emit Transfer(address(0), address(this), tokenId);
        // burn-ish
        emit Transfer(address(this), address(0), tokenId);
    }

    /// @dev Interface identification is specified in ERC-165.
    /// @param _interfaceID Id of the interface
    function supportsInterface(
        bytes4 _interfaceID
    ) external view returns (bool) {
        return supportedInterfaces[_interfaceID];
    }

    function updateAmountTobeLocked(
        uint256 _amountTobeLocked
    ) public onlyOwner {
        amountTobeLocked = _amountTobeLocked;
    }

    function updateCanCreateFractal(bool _canCreateFractals) public onlyOwner {
        canCreateFractals = _canCreateFractals;
    }

    /// @notice Get the most recently recorded rate of voting power decrease for `_tokenId`
    /// @param _tokenId token of the NFT
    /// @return Value of the slope
    function get_last_token_slope(uint _tokenId) external view returns (int128) {
        uint uepoch = token_point_epoch[_tokenId];
        return token_point_history[_tokenId][uepoch].slope;
    }

    /// @notice Get the timestamp for checkpoint `_idx` for `_tokenId`
    /// @param _tokenId token of the NFT
    /// @param _idx User epoch number
    /// @return Epoch time of the checkpoint
    function token_point_history__ts(
        uint _tokenId,
        uint _idx
    ) external view returns (uint) {
        return token_point_history[_tokenId][_idx].ts;
    }

    /// @notice Get timestamp when `_tokenId`'s lock finishes
    /// @param _tokenId User NFT
    /// @return Epoch time of the lock end
    function locked__end(uint _tokenId) external view returns (uint) {
        return locked[_tokenId].end;
    }

    /// @dev Returns the number of NFTs owned by `_owner`.
    ///      Throws if `_owner` is the zero address. NFTs assigned to the zero address are considered invalid.
    /// @param _owner Address for whom to query the balance.
    function _balance(address _owner) internal view returns (uint) {
        return ownerToNFTokenCount[_owner];
    }

    /// @dev Returns the number of NFTs owned by `_owner`.
    ///      Throws if `_owner` is the zero address. NFTs assigned to the zero address are considered invalid.
    /// @param _owner Address for whom to query the balance.
    function balanceOf(address _owner) external view returns (uint) {
        return _balance(_owner);
    }

    /// @dev Returns the address of the owner of the NFT.
    /// @param _tokenId The identifier for an NFT.
    function ownerOf(uint _tokenId) public view returns (address) {
        return idToOwner[_tokenId];
    }

    /// @dev Get the approved address for a single NFT.
    /// @param _tokenId ID of the NFT to query the approval of.
    function getApproved(uint _tokenId) external view returns (address) {
        return idToApprovals[_tokenId];
    }

    /// @dev Checks if `_operator` is an approved operator for `_owner`.
    /// @param _owner The address that owns the NFTs.
    /// @param _operator The address that acts on behalf of the owner.
    function isApprovedForAll(
        address _owner,
        address _operator
    ) external view returns (bool) {
        return (ownerToOperators[_owner])[_operator];
    }

    /// @dev  Get token by index
    function tokenOfOwnerByIndex(
        address _owner,
        uint _tokenIndex
    ) external view returns (uint) {
        return ownerToNFTokenIdList[_owner][_tokenIndex];
    }

    /// @dev Returns whether the given spender can transfer a given token ID
    /// @param _spender address of the spender to query
    /// @param _tokenId uint ID of the token to be transferred
    /// @return bool whether the msg.sender is approved for the given token ID, is an operator of the owner, or is the owner of the token
    function _isApprovedOrOwner(
        address _spender,
        uint _tokenId
    ) internal view returns (bool) {
        address owner = idToOwner[_tokenId];
        bool spenderIsOwner = owner == _spender;
        bool spenderIsApproved = _spender == idToApprovals[_tokenId];
        bool spenderIsApprovedForAll = (ownerToOperators[owner])[_spender];
        return spenderIsOwner || spenderIsApproved || spenderIsApprovedForAll;
    }

    function isApprovedOrOwner(
        address _spender,
        uint _tokenId
    ) external view returns (bool) {
        return _isApprovedOrOwner(_spender, _tokenId);
    }

    /// @dev Add a NFT to an index mapping to a given address
    /// @param _to address of the receiver
    /// @param _tokenId uint ID Of the token to be added
    function _addTokenToOwnerList(address _to, uint _tokenId) internal {
        uint current_count = _balance(_to);

        ownerToNFTokenIdList[_to][current_count] = _tokenId;
        tokenToOwnerIndex[_tokenId] = current_count;
    }

    /// @dev Remove a NFT from an index mapping to a given address
    /// @param _from address of the sender
    /// @param _tokenId uint ID Of the token to be removed
    function _removeTokenFromOwnerList(address _from, uint _tokenId) internal {
        // Delete
        uint current_count = _balance(_from) - 1;
        uint current_index = tokenToOwnerIndex[_tokenId];

        if (current_count == current_index) {
            // update ownerToNFTokenIdList
            ownerToNFTokenIdList[_from][current_count] = 0;
            // update tokenToOwnerIndex
            tokenToOwnerIndex[_tokenId] = 0;
        } else {
            uint lastTokenId = ownerToNFTokenIdList[_from][current_count];

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

    /// @dev Add a NFT to a given address
    ///      Throws if `_tokenId` is owned by someone.
    function _addTokenTo(address _to, uint _tokenId) internal {
        // Throws if `_tokenId` is owned by someone
        assert(idToOwner[_tokenId] == address(0));
        // Change the owner
        idToOwner[_tokenId] = _to;
        // Update owner token index tracking
        _addTokenToOwnerList(_to, _tokenId);
        // Change count tracking
        ownerToNFTokenCount[_to] += 1;
    }

    /// @dev Remove a NFT from a given address
    ///      Throws if `_from` is not the current owner.
    function _removeTokenFrom(address _from, uint _tokenId) internal {
        // Throws if `_from` is not the current owner
        assert(idToOwner[_tokenId] == _from);
        // Change the owner
        idToOwner[_tokenId] = address(0);
        // Update owner token index tracking
        _removeTokenFromOwnerList(_from, _tokenId);
        // Change count tracking
        ownerToNFTokenCount[_from] -= 1;
    }

    /// @dev Clear an approval of a given address
    ///      Throws if `_owner` is not the current owner.
    function _clearApproval(address _owner, uint _tokenId) internal {
        // Throws if `_owner` is not the current owner
        assert(idToOwner[_tokenId] == _owner);
        if (idToApprovals[_tokenId] != address(0)) {
            // Reset approvals
            idToApprovals[_tokenId] = address(0);
        }
    }

    /// @dev Exeute transfer of a NFT.
    ///      Throws unless `msg.sender` is the current owner, an authorized operator, or the approved
    ///      address for this NFT. (NOTE: `msg.sender` not allowed in internal function so pass `_sender`.)
    ///      Throws if `_to` is the zero address.
    ///      Throws if `_from` is not the current owner.
    ///      Throws if `_tokenId` is not a valid NFT.
    function _transferFrom(
        address _from,
        address _to,
        uint _tokenId,
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

    /* TRANSFER FUNCTIONS */
    /// @dev Throws unless `msg.sender` is the current owner, an authorized operator, or the approved address for this NFT.
    ///      Throws if `_from` is not the current owner.
    ///      Throws if `_to` is the zero address.
    ///      Throws if `_tokenId` is not a valid NFT.
    /// @notice The caller is responsible to confirm that `_to` is capable of receiving NFTs or else
    ///        they maybe be permanently lost.
    /// @param _from The current owner of the NFT.
    /// @param _to The new owner.
    /// @param _tokenId The NFT to transfer.
    function transferFrom(address _from, address _to, uint _tokenId) external {
        _transferFrom(_from, _to, _tokenId, msg.sender);
    }

    function _isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.
        uint size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    /// @dev Transfers the ownership of an NFT from one address to another address.
    ///      Throws unless `msg.sender` is the current owner, an authorized operator, or the
    ///      approved address for this NFT.
    ///      Throws if `_from` is not the current owner.
    ///      Throws if `_to` is the zero address.
    ///      Throws if `_tokenId` is not a valid NFT.
    ///      If `_to` is a smart contract, it calls `onERC721Received` on `_to` and throws if
    ///      the return value is not `bytes4(keccak256("onERC721Received(address,address,uint,bytes)"))`.
    /// @param _from The current owner of the NFT.
    /// @param _to The new owner.
    /// @param _tokenId The NFT to transfer.
    /// @param _data Additional data with no specified format, sent in call to `_to`.
    function safeTransferFrom(
        address _from,
        address _to,
        uint _tokenId,
        bytes memory _data
    ) public {
        _transferFrom(_from, _to, _tokenId, msg.sender);

        if (_isContract(_to)) {
            // Throws if transfer destination is a contract which does not implement 'onERC721Received'
            try
                IERC721Receiver(_to).onERC721Received(
                    msg.sender,
                    _from,
                    _tokenId,
                    _data
                )
            returns (bytes4) {} catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert(
                        "ERC721: transfer to non ERC721Receiver implementer"
                    );
                } else {
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        }
    }

    /// @dev Transfers the ownership of an NFT from one address to another address.
    ///      Throws unless `msg.sender` is the current owner, an authorized operator, or the
    ///      approved address for this NFT.
    ///      Throws if `_from` is not the current owner.
    ///      Throws if `_to` is the zero address.
    ///      Throws if `_tokenId` is not a valid NFT.
    ///      If `_to` is a smart contract, it calls `onERC721Received` on `_to` and throws if
    ///      the return value is not `bytes4(keccak256("onERC721Received(address,address,uint,bytes)"))`.
    /// @param _from The current owner of the NFT.
    /// @param _to The new owner.
    /// @param _tokenId The NFT to transfer.
    function safeTransferFrom(
        address _from,
        address _to,
        uint _tokenId
    ) external {
        safeTransferFrom(_from, _to, _tokenId, "");
    }

    /// @dev Set or reaffirm the approved address for an NFT. The zero address indicates there is no approved address.
    ///      Throws unless `msg.sender` is the current NFT owner, or an authorized operator of the current owner.
    ///      Throws if `_tokenId` is not a valid NFT. (NOTE: This is not written the EIP)
    ///      Throws if `_approved` is the current owner. (NOTE: This is not written the EIP)
    /// @param _approved Address to be approved for the given NFT ID.
    /// @param _tokenId ID of the token to be approved.
    function approve(address _approved, uint _tokenId) public {
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

    /// @dev Enables or disables approval for a third party ("operator") to manage all of
    ///      `msg.sender`'s assets. It also emits the ApprovalForAll event.
    ///      Throws if `_operator` is the `msg.sender`. (NOTE: This is not written the EIP)
    /// @notice This works even if sender doesn't own any tokens at the time.
    /// @param _operator Address to add to the set of authorized operators.
    /// @param _approved True if the operators is approved, false to revoke approval.
    function setApprovalForAll(address _operator, bool _approved) external {
        // Throws if `_operator` is the `msg.sender`
        assert(_operator != msg.sender);
        ownerToOperators[msg.sender][_operator] = _approved;
        emit ApprovalForAll(msg.sender, _operator, _approved);
    }

    /// @dev Function to mint tokens
    ///      Throws if `_to` is zero address.
    ///      Throws if `_tokenId` is owned by someone.
    /// @param _to The address that will receive the minted tokens.
    /// @param _tokenId The token id to mint.
    /// @return A boolean that indicates if the operation was successful.
    function _mint(address _to, uint _tokenId) internal returns (bool) {
        // Throws if `_to` is zero address
        assert(_to != address(0));
        // Add NFT. Throws if `_tokenId` is owned by someone
        _addTokenTo(_to, _tokenId);
        emit Transfer(address(0), _to, _tokenId);
        return true;
    }

    /// @notice Deposit and lock tokens for a user
    /// @param _tokenId NFT that holds lock
    /// @param _value Amount to deposit
    /// @param locked_balance Previous locked amount / timestamp
    /// @param deposit_type The type of deposit
    function _deposit_for(
        uint _tokenId,
        uint _value,
        LockedBalance memory locked_balance,
        DepositType deposit_type
    ) internal {
        LockedBalance memory _locked = locked_balance;
        uint supply_before = supply;

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

        address from = msg.sender;
        if (_value != 0 && deposit_type != DepositType.MERGE_TYPE) {
            IERC20(token).safeTransferFrom(from, address(this), _value);
        }

        emit Deposit(
            from,
            _tokenId,
            _value,
            _locked.end,
            deposit_type,
            block.timestamp
        );
        emit Supply(supply_before, supply_before + _value);
    }

    function locking(uint256 _tokenId) external view returns (int256) {
        LockedBalance memory _locked = locked[_tokenId];

        return _locked.amount;
    }

    function setVoter(address _voter) external {
        require(msg.sender == voter);
        voter = _voter;
    }

    function voting(uint _tokenId) external {
        require(msg.sender == voter);
        voted[_tokenId] = true;
    }

    function attach(uint _tokenId) external {
        require(msg.sender == voter);
        attachments[_tokenId] = attachments[_tokenId] + 1;
    }

    function detach(uint _tokenId) external {
        require(msg.sender == voter);
        attachments[_tokenId] = attachments[_tokenId] - 1;
    }

    function block_number() external view returns (uint) {
        return block.number;
    }

    /// @notice Deposit `_value` tokens for `_to` and lock for `_lock_duration`
    /// @param _value Amount to deposit
    /// @param _to Address to deposit
    function _create_lock(uint _value, address _to) internal returns (uint) {
        require(
            _value == amountTobeLocked,
            "The value must equal to amountTobeLocked"
        );
        require(canCreateFractals == true, "canCreateFractals must be true");
        require(_value > 0); // dev: need non-zero value

        ++tokenId;
        uint _tokenId = tokenId;
        _mint(_to, _tokenId);

        _deposit_for(
            _tokenId,
            _value,
            locked[_tokenId],
            DepositType.CREATE_LOCK_TYPE
        );
        return _tokenId;
    }

    /// @notice Deposit `_value` tokens for `_to` and lock for `_lock_duration`
    /// @param _value Amount to deposit
    /// @param _to Address to deposit
    function create_lock_for(
        uint _value,
        address _to
    ) external nonreentrant returns (uint) {
        return _create_lock(_value, _to);
    }

    /// @notice Deposit `_value` tokens for `msg.sender` and lock for `_lock_duration`
    /// @param _value Amount to deposit
    function create_lock(uint _value) external nonreentrant returns (uint) {
        return _create_lock(_value, msg.sender);
    }

    // The following ERC20/minime-compatible methods are not real balanceOf and supply!
    // They measure the weights for the purpose of voting, so they don't represent
    // real coins.

    /// @notice Binary search to estimate timestamp for block number
    /// @param _block Block to find
    /// @param max_epoch Don't go beyond this epoch
    /// @return Approximate timestamp for block
    function _find_block_epoch(
        uint _block,
        uint max_epoch
    ) internal view returns (uint) {
        // Binary search
        uint _min = 0;
        uint _max = max_epoch;
        for (uint i = 0; i < 128; ++i) {
            // Will be always enough for 128-bit numbers
            if (_min >= _max) {
                break;
            }
            uint _mid = (_min + _max + 1) / 2;
            if (point_history[_mid].blk <= _block) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }
        return _min;
    }

    /// @notice Get the current voting power for `_tokenId`
    /// @dev Adheres to the ERC20 `balanceOf` interface for Aragon compatibility
    /// @param _tokenId NFT for lock
    /// @param _t Epoch time to return voting power at
    /// @return User voting power
    function _balanceOfNFT(
        uint _tokenId,
        uint _t
    ) internal view returns (uint) {
        uint _epoch = token_point_epoch[_tokenId];
        if (_epoch == 0) {
            return 0;
        } else {
            Point memory last_point = token_point_history[_tokenId][_epoch];
            last_point.bias -=
                last_point.slope *
                int128(int256(_t) - int256(last_point.ts));
            if (last_point.bias < 0) {
                last_point.bias = 0;
            }
            return uint(int256(last_point.bias));
        }
    }

    /// @dev Returns current token URI metadata
    /// @param _tokenId Token ID to fetch URI for.
    function tokenURI(uint _tokenId) external view returns (string memory) {
        require(
            idToOwner[_tokenId] != address(0),
            "Query for nonexistent token"
        );
        LockedBalance memory _locked = locked[_tokenId];
        return
            _tokenURI(
                _tokenId,
                _balanceOfNFT(_tokenId, block.timestamp),
                _locked.end,
                uint(int256(_locked.amount))
            );
    }

    function balanceOfNFT(uint _tokenId) external view returns (uint) {
        if (ownership_change[_tokenId] == block.number) return 0;
        return _balanceOfNFT(_tokenId, block.timestamp);
    }

    function balanceOfNFTAt(
        uint _tokenId,
        uint _t
    ) external view returns (uint) {
        return _balanceOfNFT(_tokenId, _t);
    }

    /// @notice Measure voting power of `_tokenId` at block height `_block`
    /// @dev Adheres to MiniMe `balanceOfAt` interface: https://github.com/Giveth/minime
    /// @param _tokenId User's wallet NFT
    /// @param _block Block to calculate the voting power at
    /// @return Voting power
    function _balanceOfAtNFT(
        uint _tokenId,
        uint _block
    ) internal view returns (uint) {
        // Copying and pasting totalSupply code because Vyper cannot pass by
        // reference yet
        assert(_block <= block.number);

        // Binary search
        uint _min = 0;
        uint _max = token_point_epoch[_tokenId];
        for (uint i = 0; i < 128; ++i) {
            // Will be always enough for 128-bit numbers
            if (_min >= _max) {
                break;
            }
            uint _mid = (_min + _max + 1) / 2;
            if (token_point_history[_tokenId][_mid].blk <= _block) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }

        Point memory upoint = token_point_history[_tokenId][_min];

        uint max_epoch = epoch;
        uint _epoch = _find_block_epoch(_block, max_epoch);
        Point memory point_0 = point_history[_epoch];
        uint d_block = 0;
        uint d_t = 0;
        if (_epoch < max_epoch) {
            Point memory point_1 = point_history[_epoch + 1];
            d_block = point_1.blk - point_0.blk;
            d_t = point_1.ts - point_0.ts;
        } else {
            d_block = block.number - point_0.blk;
            d_t = block.timestamp - point_0.ts;
        }
        uint block_time = point_0.ts;
        if (d_block != 0) {
            block_time += (d_t * (_block - point_0.blk)) / d_block;
        }

        upoint.bias -= upoint.slope * int128(int256(block_time - upoint.ts));
        if (upoint.bias >= 0) {
            return uint(uint128(upoint.bias));
        } else {
            return 0;
        }
    }

    function balanceOfAtNFT(
        uint _tokenId,
        uint _block
    ) external view returns (uint) {
        return _balanceOfAtNFT(_tokenId, _block);
    }

    /// @notice Calculate total voting power at some point in the past
    /// @param point The point (bias/slope) to start search from
    /// @param t Time to calculate the total voting power at
    /// @return Total voting power at that time
    function _supply_at(
        Point memory point,
        uint t
    ) internal view returns (uint) {
        Point memory last_point = point;
        uint t_i = (last_point.ts / WEEK) * WEEK;
        for (uint i = 0; i < 255; ++i) {
            t_i += WEEK;
            int128 d_slope = 0;
            if (t_i > t) {
                t_i = t;
            } else {
                d_slope = slope_changes[t_i];
            }
            last_point.bias -=
                last_point.slope *
                int128(int256(t_i - last_point.ts));
            if (t_i == t) {
                break;
            }
            last_point.slope += d_slope;
            last_point.ts = t_i;
        }

        if (last_point.bias < 0) {
            last_point.bias = 0;
        }
        return uint(uint128(last_point.bias));
    }

    /// @notice Calculate total voting power
    /// @dev Adheres to the ERC20 `totalSupply` interface for Aragon compatibility
    /// @return Total voting power
    function totalSupplyAtT(uint t) public view returns (uint) {
        uint _epoch = epoch;
        Point memory last_point = point_history[_epoch];
        return _supply_at(last_point, t);
    }

    function totalSupply() external view returns (uint) {
        return totalSupplyAtT(block.timestamp);
    }

    /// @notice Calculate total voting power at some point in the past
    /// @param _block Block to calculate the total voting power at
    /// @return Total voting power at `_block`
    function totalSupplyAt(uint _block) external view returns (uint) {
        assert(_block <= block.number);
        uint _epoch = epoch;
        uint target_epoch = _find_block_epoch(_block, _epoch);

        Point memory point = point_history[target_epoch];
        uint dt = 0;
        if (target_epoch < _epoch) {
            Point memory point_next = point_history[target_epoch + 1];
            if (point.blk != point_next.blk) {
                dt =
                    ((_block - point.blk) * (point_next.ts - point.ts)) /
                    (point_next.blk - point.blk);
            }
        } else {
            if (point.blk != block.number) {
                dt =
                    ((_block - point.blk) * (block.timestamp - point.ts)) /
                    (block.number - point.blk);
            }
        }
        // Now dt contains info on how far are we beyond point
        return _supply_at(point, point.ts + dt);
    }

    function _tokenURI(
        uint _tokenId,
        uint _balanceOf,
        uint _locked_end,
        uint _value
    ) internal pure returns (string memory output) {
        output = '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350"><style>.base { fill: white; font-family: serif; font-size: 14px; }</style><rect width="100%" height="100%" fill="black" /><text x="10" y="20" class="base">';
        output = string(
            abi.encodePacked(
                output,
                "token ",
                toString(_tokenId),
                '</text><text x="10" y="40" class="base">'
            )
        );
        output = string(
            abi.encodePacked(
                output,
                "balanceOf ",
                toString(_balanceOf),
                '</text><text x="10" y="60" class="base">'
            )
        );
        output = string(
            abi.encodePacked(
                output,
                "locked_end ",
                toString(_locked_end),
                '</text><text x="10" y="80" class="base">'
            )
        );
        output = string(
            abi.encodePacked(
                output,
                "value ",
                toString(_value),
                "</text></svg>"
            )
        );

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
        output = string(
            abi.encodePacked("data:application/json;base64,", json)
        );
    }

    function toString(uint value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT license
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint temp = value;
        uint digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function _burn(uint _tokenId) internal {
        require(
            _isApprovedOrOwner(msg.sender, _tokenId),
            "caller is not owner nor approved"
        );

        address owner = ownerOf(_tokenId);

        // Clear approval
        approve(address(0), _tokenId);
        // Remove token
        _removeTokenFrom(msg.sender, _tokenId);
        emit Transfer(owner, address(0), _tokenId);
    }
}

contract AraEmissionDistributor is AccessControl, Ownable {
    using SafeERC20 for IERC20;

    // TokenInfo Struct
    struct TokenInfo {
        address user; // address from the owner of this araFractalV2
        uint256 numberNFT; // TokenId araFractalV2
    }

    /******************** AnotherToken Structs **********************/
    struct PoolInfoAnotherToken {
        address tokenReward; // address from the Reward of this each Pool
        uint256 anotherTokenPerBlock; // How much AnotherTokens Per Block
        uint256 allocPoint; // How many allocation points assigned to this pool. the fraction AnotherToken to distribute per block.
        uint256 lastRewardBlock; // Last block number that AnotherToken distribution occurs.
        uint256 accAnotherTokenPerShare; // Accumulated ARA per araFractalV2. this is multiplied by ACC_ANOTHERTOKEN_PRECISION for more exact results (rounding errors)
    }

    struct UserInfoAnotherToken {
        uint256 amount; // How many ARA locked by the user on veARA.
        uint256 rewardDebt; // AnotherToken Reward debt.
    }
    /****************************************************************/

    uint256 public totalPidsAnotherToken = 0; // total number of another token pools
    mapping(uint256 => PoolInfoAnotherToken) public poolInfoAnotherToken; // an array to store information of all pools of another token
    mapping(uint256 => mapping(address => mapping(uint256 => UserInfoAnotherToken)))
        public userInfoAnotherToken; // mapping form poolId => user Address => User Info

    uint256 public tokenInfoCount = 0;
    mapping(uint256 => TokenInfo) public tokenInfo;


    uint256 public totalAnotherAllocPoint = 0;

    mapping(address => uint256[]) public tokenIdsByUser;

    mapping(address => uint256) public totalNftsByUser;

    uint256 private constant ACC_ANOTHERTOKEN_PRECISION = 1e12; // precision used for calculations involving another token
    // uint256 public constant POOL_PERCENTAGE = 0.876e3; // Percentage of ARA allocated to pools

    uint256 public constant DENOMINATOR = 1e3; // Constant denominator for calculating allocation points

    IERC721 public araFractalV2; // araFractalV2 ERC721 token

    /* AnotherToken Rewards Events*/
    event LogSetPoolAnotherToken(
        uint256 indexed pid,
        address indexed tokenReward,
        uint256 allocPoint
    );
    event LogPoolAnotherTokenAddition(
        uint256 indexed pid,
        address indexed tokenReward,
        uint256 allocPoint
    );
    event DepositAnotherToken(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        address indexed to
    );
    event WithdrawAnotherToken(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        address indexed to
    );
    event HarvestAnotherToken(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    event LogUpdatePoolAnotherToken(
        uint256 indexed pid,
        uint256 lastRewardBlock,
        uint256 accARAPerShare
    );

    /* General Events */
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    error AraZeroAddress();
    error NotOwnerOfveARA();
    error InvalidPoolId();
    error InsufficientRewardtokens();

    constructor(
        IERC721 _araFractalV2 // araFractalV2 ERC721 token
    ) {
        if(address(_araFractalV2) == address(0)){
            revert AraZeroAddress();
        }
        araFractalV2 = _araFractalV2;
    }

    // Function to deposit veARA token to the contract and receive rewards
    function depositToChef(uint256 _pid, uint256 _tokenId) external {
        if(_pid >= totalPidsAnotherToken) {
            revert InvalidPoolId();
        }
        // Check if msg.sender is the owner of the veARA
        address ownerOfTokenId = IERC721(araFractalV2).ownerOf(_tokenId);
        if(ownerOfTokenId != msg.sender) {
            revert NotOwnerOfveARA();
        }

        // AnotherToken Rewards attributes
        PoolInfoAnotherToken memory poolAnotherToken = updatePoolAnotherToken(
            _pid
        );
        UserInfoAnotherToken storage userAnotherToken = userInfoAnotherToken[
            _pid
        ][msg.sender][_tokenId];

        totalNftsByUser[msg.sender] = totalNftsByUser[msg.sender] + 1;
        tokenIdsByUser[msg.sender].push(_tokenId);

        // Transfer the veARA token from the user to the contract
        ve(address(araFractalV2)).transferFrom(
            msg.sender,
            address(this),
            _tokenId
        );
        uint256 amount = uint256(ve(address(araFractalV2)).locking(_tokenId));

        /******************** AnotherToken Rewards Code ********************/
        // AnotherToken Rewards Code
        userAnotherToken.amount = userAnotherToken.amount + amount;
        userAnotherToken.rewardDebt =
            userAnotherToken.rewardDebt +
            (amount * poolAnotherToken.accAnotherTokenPerShare) /
            ACC_ANOTHERTOKEN_PRECISION;
        /*******************************************************************/

        // Push the tokenInfo to the tokenInfo array
        tokenInfo[tokenInfoCount] = TokenInfo({user: msg.sender, numberNFT: _tokenId});
        tokenInfoCount ++;

        // Events
        // Emit events for deposit
        emit DepositAnotherToken(msg.sender, _pid, amount, msg.sender);
    }

    function depositAnotherToken(
        uint256 _pid,
        uint256 _amount
    ) external onlyOwner {
        if(_pid >= totalPidsAnotherToken) {
            revert InvalidPoolId();
        }
        PoolInfoAnotherToken storage poolAnotherToken = poolInfoAnotherToken[
            _pid
        ];
        IERC20(poolAnotherToken.tokenReward).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        emit DepositAnotherToken(msg.sender, _pid, _amount, msg.sender);
    }

    function withdrawAndDistribute(uint256 _pid, uint256 _tokenId) external {
        // AnotherToken Rewards attributes
        if(_pid >= totalPidsAnotherToken) {
            revert InvalidPoolId();
        }
        PoolInfoAnotherToken memory poolAnotherToken = updatePoolAnotherToken(
            _pid
        );
        UserInfoAnotherToken storage userAnotherToken = userInfoAnotherToken[
            _pid
        ][msg.sender][_tokenId];

        uint256 amount = uint256(ve(address(araFractalV2)).locking(_tokenId)); // amount of locked ARA on that veARA

        /******************** AnotherToken Rewards Code ********************/
        uint256 accumulatedWAnotherToken = (userAnotherToken.amount *
            poolAnotherToken.accAnotherTokenPerShare) /
            ACC_ANOTHERTOKEN_PRECISION;
        // subtracting the rewards the user is not eligible for
        uint256 eligibleAnotherToken = accumulatedWAnotherToken -
            userAnotherToken.rewardDebt;
        userAnotherToken.amount = userAnotherToken.amount - amount; // put user amount of UserInfo a zero
        userAnotherToken.rewardDebt =
            (userAnotherToken.amount *
                poolAnotherToken.accAnotherTokenPerShare) /
            ACC_ANOTHERTOKEN_PRECISION; // update AnotherToken Reward Debt
        safeAnotherTokenTransfer(_pid, msg.sender, eligibleAnotherToken);
        /********************************************************************/

        IERC721(araFractalV2).safeTransferFrom(
            address(this),
            msg.sender,
            _tokenId
        ); // transfer veARA to his owner

        uint256[] storage tokenIdsByCaller = tokenIdsByUser[msg.sender];
        for (uint256 i = 0; i < tokenIdsByCaller.length; ) {
            if (tokenIdsByCaller[i] == _tokenId) {
                // Swap the element to remove with the last element
                tokenIdsByCaller[i] = tokenIdsByCaller[
                    tokenIdsByCaller.length - 1
                ];
                // Pop the last element from the array
                tokenIdsByCaller.pop();
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

    function harvestAndDistributeAnotherToken(
        uint256 _pid,
        uint256 _tokenId
    ) external {
        if(_pid >= totalPidsAnotherToken) {
            revert InvalidPoolId();
        }
        // Get the current pool information for the specified pid
        PoolInfoAnotherToken memory poolAnotherToken = updatePoolAnotherToken(
            _pid
        );
        // Get the current user's information for the specified pid and tokenId
        UserInfoAnotherToken storage userAnotherToken = userInfoAnotherToken[
            _pid
        ][msg.sender][_tokenId];

        // Calculate the total accumulated AnotherToken rewards for the user based on their LP token amount
        uint256 accumulatedAnotherToken = (userAnotherToken.amount *
            poolAnotherToken.accAnotherTokenPerShare) /
            ACC_ANOTHERTOKEN_PRECISION;
        // Subtract any rewards the user is not eligible for
        uint256 eligibleAnotherToken = accumulatedAnotherToken -
            userAnotherToken.rewardDebt;

        // Update the user's reward debt to the current accumulated AnotherToken rewards
        userAnotherToken.rewardDebt = accumulatedAnotherToken;

        // If there are any eligible AnotherToken rewards, transfer them to the user
        if (eligibleAnotherToken > 0) {
            safeAnotherTokenTransfer(_pid, msg.sender, eligibleAnotherToken);
        }

        // Emit an event to log the harvest
        emit HarvestAnotherToken(msg.sender, _pid, eligibleAnotherToken);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid, uint256 _tokenId) external {
        if(_pid >= totalPidsAnotherToken) {
            revert InvalidPoolId();
        }
        // Get the current user's information for the specified pid and tokenId
        UserInfoAnotherToken storage userAnotherToken = userInfoAnotherToken[
            _pid
        ][msg.sender][_tokenId];
        // Get the current user's LP token amount
        userAnotherToken.amount = 0;
        userAnotherToken.rewardDebt = 0;
        // Transfer the user's LP token back to them using the IERC721 contract
        IERC721(araFractalV2).safeTransferFrom(
            address(this),
            msg.sender,
            _tokenId
        );

        uint256[] storage tokenIdsByCaller = tokenIdsByUser[msg.sender];
        for (uint256 i = 0; i < tokenIdsByCaller.length; ) {
            if (tokenIdsByCaller[i] == _tokenId) {
                // Swap the element to remove with the last element
                tokenIdsByCaller[i] = tokenIdsByCaller[
                    tokenIdsByCaller.length - 1
                ];
                // Pop the last element from the array
                tokenIdsByCaller.pop();
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
        uint256 _allocPoint
    ) external onlyOwner {
        // Add a new pool with the specified token reward, block reward, closed status, allocation point and current timestamp to the poolInfoAnotherToken array
        poolInfoAnotherToken[totalPidsAnotherToken] = 
            PoolInfoAnotherToken({
                tokenReward: _tokenReward,
                anotherTokenPerBlock: _anotherTokenPerBlock,
                allocPoint: _allocPoint,
                lastRewardBlock: block.number,
                accAnotherTokenPerShare: 0
            });

        totalPidsAnotherToken++;
        totalAnotherAllocPoint = totalAnotherAllocPoint + _allocPoint;
        // Emit an event to log the pool addition
        emit LogPoolAnotherTokenAddition(
            totalPidsAnotherToken - 1,
            _tokenReward,
            _allocPoint
        );
    }

    // Update the given Another Token pool's. Can only be called by the owner.
    function setAnotherToken(
        uint256 _pid,
        address _tokenReward,
        uint256 _allocPoint,
        uint256 _anotherTokenPerBlock
    ) external onlyOwner {
        if(_pid >= totalPidsAnotherToken) {
            revert InvalidPoolId();
        }
        // Update the allocation point, token reward, block reward and closed status of the specified AnotherToken pool
        PoolInfoAnotherToken storage poolAnotherToken = poolInfoAnotherToken[
            _pid
        ];
        poolAnotherToken.allocPoint = _allocPoint;
        poolAnotherToken.tokenReward = _tokenReward;
        poolAnotherToken.anotherTokenPerBlock = _anotherTokenPerBlock;
        totalAnotherAllocPoint = totalAnotherAllocPoint + _allocPoint;
        // Emit an event to log the pool update
        emit LogSetPoolAnotherToken(_pid, _tokenReward, _allocPoint);
    }

    // View function to see the pending AnotherToken rewards for a user
    function pendingAnotherToken(
        uint256 _pid,
        uint256 _tokenId,
        address _user
    ) external view returns (uint256 pending) {
        PoolInfoAnotherToken storage poolAnotherToken = poolInfoAnotherToken[
            _pid
        ];
        UserInfoAnotherToken storage userAnotherToken = userInfoAnotherToken[
            _pid
        ][_user][_tokenId];
        // Get the accumulated AnotherToken per LP token
        uint256 accAnotherTokenPerShare = poolAnotherToken
            .accAnotherTokenPerShare;
        // Calculate the pending AnotherToken rewards for the user based on their staked LP tokens and
        // subtracting any rewards they are not eligible for or have already claimed
        uint256 anotherTokenSupply = IERC20(
            poolInfoAnotherToken[_pid].tokenReward
        ).balanceOf(address(this));

        if (
            block.number > poolAnotherToken.lastRewardBlock &&
            anotherTokenSupply > 0
        ) {
            uint256 blocksSinceLastReward = block.number -
                poolAnotherToken.lastRewardBlock;
            // based on the pool weight (allocation points) we calculate the anotherToken rewarded for this specific pool
            uint256 anotherTokenRewards = (blocksSinceLastReward +
                poolAnotherToken.anotherTokenPerBlock *
                poolAnotherToken.allocPoint) / totalAnotherAllocPoint;
            // we take parts of the rewards for treasury, these can be subject to change, so we recalculate it a value of 1000 = 100%
            uint256 anotherTokenRewardsForPool = (anotherTokenRewards *
                DENOMINATOR) / DENOMINATOR;

            // we calculate the new amount of accumulated anotherToken per veARA
            accAnotherTokenPerShare =
                accAnotherTokenPerShare +
                ((anotherTokenRewardsForPool * ACC_ANOTHERTOKEN_PRECISION) /
                    anotherTokenSupply);
        }
        // Calculate the pending AnotherToken rewards for the user based on their staked LP tokens and subtracting any rewards they are not eligible for or have already claimed
        pending =
            (userAnotherToken.amount * accAnotherTokenPerShare) /
            ACC_ANOTHERTOKEN_PRECISION -
            userAnotherToken.rewardDebt;
    }

    // Update reward variables of the given anotherToken pool to be up-to-date.
    function updatePoolAnotherToken(
        uint256 _pid
    ) public returns (PoolInfoAnotherToken memory poolAnotherToken) {
        poolAnotherToken = poolInfoAnotherToken[_pid];

        if (block.number > poolAnotherToken.lastRewardBlock) {
            // total of AnotherTokens staked for this pool
            uint256 anotherTokenSupply = IERC20(
                poolInfoAnotherToken[_pid].tokenReward
            ).balanceOf(address(this));
            if (anotherTokenSupply > 0) {
                uint256 blocksSinceLastReward = block.number -
                    poolAnotherToken.lastRewardBlock;

                // rewards for this pool based on his allocation points
                uint256 anotherTokenRewards = (blocksSinceLastReward *
                    poolAnotherToken.anotherTokenPerBlock *
                    poolAnotherToken.allocPoint) / totalAnotherAllocPoint;

                uint256 anotherTokenRewardsForPool = (anotherTokenRewards *
                    DENOMINATOR) / DENOMINATOR;

                poolAnotherToken.accAnotherTokenPerShare =
                    poolAnotherToken.accAnotherTokenPerShare +
                    ((anotherTokenRewardsForPool * ACC_ANOTHERTOKEN_PRECISION) /
                        anotherTokenSupply);
            }
            poolAnotherToken.lastRewardBlock = block.number;
            poolInfoAnotherToken[_pid] = poolAnotherToken;

            emit LogUpdatePoolAnotherToken(
                _pid,
                poolAnotherToken.lastRewardBlock,
                poolAnotherToken.accAnotherTokenPerShare
            );
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
        uint256 anotherTokenBalance = IERC20(pool.tokenReward).balanceOf(
            address(this)
        );
        if(!(anotherTokenBalance >= _amount && _amount > 0)) {
            revert InsufficientRewardtokens();
        }
        IERC20(pool.tokenReward).safeTransfer(_to, anotherTokenBalance);
    }
}
