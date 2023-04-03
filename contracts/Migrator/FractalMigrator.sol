interface IERC721Enumerable is IERC721 {

    /**
     * @dev Returns the total amount of tokens stored by the contract.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns a token ID owned by `owner` at a given `index` of its token list.
     * Use along with {balanceOf} to enumerate all of ``owner``'s tokens.
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256 tokenId);

    /**
     * @dev Returns a token ID at a given `index` of all the tokens stored by the contract.
     * Use along with {totalSupply} to enumerate all tokens.
     */
    function tokenByIndex(uint256 index) external view returns (uint256);
}

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC721 standard as defined in the EIP.
 */
interface IERC721 {
    /**
     * @dev Returns the number of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the owner of the token.
     */
    function ownerOf(uint256 tokenId) external view returns (address);

    /**
     * @dev Transfers `tokenId` token from `from` to `to`.
     *
     * Requirements:
     *
     * - `from` must be the owner of the token.
     */
    function transferFrom(address from, address to, uint256 tokenId) external;
}

contract TokenSwap {
    IERC721 public oldToken;
    IERC721 public newToken;
    address public owner;
    address public receiver;
    uint256 _tokenIdGeneral;

    constructor(address  _oldTokenAddress, address _newTokenAddress, address _receiver) {
        oldToken = IERC721(_oldTokenAddress);
        newToken = IERC721(_newTokenAddress);
        owner = msg.sender;
        receiver = _receiver;
        _tokenIdGeneral = 0;
    }

    function balance(uint256 _tokenId) public view returns(bool) {
        return oldToken.ownerOf(_tokenId) == msg.sender;
    }

    function approveAllOldTokens(uint256 numTokens) public {
        for (uint256 i = 0; i < numTokens; i++) {
            uint256 oldTokenId = tokenOfOwnerByIndex(address(msg.sender),i);
            oldToken.approve(address(this), oldTokenId);
            }
        }

    function swap(uint256 numOldTokens) public {
        require(numOldTokens > 0, "Must send at least one old token");
        require(numOldTokens == oldToken.balanceOf(msg.sender), "Incorrect number of old tokens sent");
    
        // Transfer old tokens to contract
        for (uint256 i = 0; i < numOldTokens; i++) {
            uint256 oldTokenId = tokenOfOwnerByIndex(address(msg.sender),i);
            require(oldToken.ownerOf(oldTokenId) == msg.sender, "Not the owner of old token");
            oldToken.transferFrom(msg.sender, address(this), oldTokenId);
        }
    
    // Transfer new tokens to user with random tokenId from user's tokens
        uint256 numNewTokens = newToken.balanceOf(address(this));
        require(numNewTokens >= numOldTokens, "Not enough new tokens in contract");
        for (uint256 i = 0; i < numOldTokens; i++) {
            uint256 randomTokenIndex = uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, i))) % numNewTokens;
            uint256 newTokenId = newToken.tokenOfOwnerByIndex(address(this), randomTokenIndex);
            newToken.safeTransferFrom(address(this), msg.sender, newTokenId);
            numNewTokens--;
        }
    }

    function withdrawOldTokens(uint256[] memory _tokenIds) public {
        require(msg.sender == owner, "Only the contract owner can withdraw new tokens.");
        for (uint i = 0; i < _tokenIds.length; i++) {
            oldToken.transferFrom(address(this), msg.sender, _tokenIds[i]);
        }
    }

    function depositNewTokens(uint256[] memory _tokenIds) public {
        require(msg.sender == owner, "Only the contract owner can deposit old tokens.");
        for (uint i = 0; i < _tokenIds.length; i++) {
            newToken.transferFrom(msg.sender, address(this), _tokenIds[i]);
        }
    }
}
