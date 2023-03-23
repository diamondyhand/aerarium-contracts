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

    constructor(address  _oldTokenAddress, address _newTokenAddress, address _receiver) {
        oldToken = IERC721(_oldTokenAddress);
        newToken = IERC721(_newTokenAddress);
        owner = msg.sender;
        receiver = _receiver;
    }

    function balance(uint256 _tokenId) public view returns(bool) {
        return oldToken.ownerOf(_tokenId) == msg.sender;
    }

    function swap(uint256 _tokenId) public {
        require(oldToken.ownerOf(_tokenId) == msg.sender, "Not the owner of old token");
        oldToken.transferFrom(msg.sender, receiver, _tokenId);
        newToken.transferFrom(owner, msg.sender, _tokenId);
    }

    function withdrawNewTokens() public {
        require(msg.sender == owner, "Only the contract owner can withdraw new tokens.");
        newToken.transferFrom(address(this), msg.sender, newToken.totalSupply());
    }
}
