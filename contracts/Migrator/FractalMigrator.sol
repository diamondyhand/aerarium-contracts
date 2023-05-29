pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC721 standard as defined in the EIP.
 */
interface IERC721 {
    function approve(address spender, uint256 tokenId) external returns (bool);

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

    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Transfers `tokenId` token from `from` to `to`.
     *
     * Requirements:
     *
     * - `from` must be the owner of the token.
     */
    function transferFrom(address from, address to, uint256 tokenId) external;
}

interface IERC721Enumerable is IERC721 {
    /**
     * @dev Returns the total amount of tokens stored by the contract.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns a token ID owned by `owner` at a given `index` of its token list.
     * Use along with {balanceOf} to enumerate all of ``owner``'s tokens.
     */
    function tokenOfOwnerByIndex(
        address owner,
        uint256 index
    ) external view returns (uint256 tokenId);

    /**
     * @dev Returns a token ID at a given `index` of all the tokens stored by the contract.
     * Use along with {totalSupply} to enumerate all tokens.
     */
    function tokenByIndex(uint256 index) external view returns (uint256);
}

contract TokenSwap {
    IERC721 public oldToken;
    IERC721 public newToken;
    address public owner;
    uint256 _tokenIdGeneral;

    constructor(address _oldTokenAddress, address _newTokenAddress) {
        oldToken = IERC721(_oldTokenAddress);
        newToken = IERC721(_newTokenAddress);
        owner = msg.sender;
        _tokenIdGeneral = 0;
    }

    function balance(uint256 _tokenId) public view returns (bool) {
        return oldToken.ownerOf(_tokenId) == msg.sender;
    }

    function swap(uint256[] memory _tokenIds) public {
        // Transfer old tokens to contract
        for (uint i = 0; i < _tokenIds.length; i++) {
            oldToken.transferFrom(msg.sender, address(this), _tokenIds[i]);
        }

        uint256 numNewTokens = newToken.balanceOf(address(this));
        require(
            numNewTokens >= _tokenIds.length,
            "Not enough new tokens in contract"
        );
        for (uint256 i = _tokenIds.length - 1; i >= 0; i--) {
            uint256 newTokenId = IERC721Enumerable(address(newToken))
                .tokenOfOwnerByIndex(address(this), i);
            newToken.transferFrom(address(this), msg.sender, newTokenId);
        }
    }

    function withdrawOldTokens(uint256[] memory _tokenIds) public {
        require(
            msg.sender == owner,
            "Only the contract owner can withdraw old tokens."
        );
        for (uint i = 0; i < _tokenIds.length; i++) {
            oldToken.transferFrom(address(this), msg.sender, _tokenIds[i]);
        }
    }

    function withdrawNewTokens(uint256[] memory _tokenIds) public {
        require(
            msg.sender == owner,
            "Only the contract owner can withdraw old tokens."
        );
        for (uint i = 0; i < _tokenIds.length; i++) {
            newToken.transferFrom(address(this), msg.sender, _tokenIds[i]);
        }
    }

    function depositNewTokens(uint256[] memory _tokenIds) public {
        for (uint i = 0; i < _tokenIds.length; i++) {
            newToken.transferFrom(msg.sender, address(this), _tokenIds[i]);
        }
    }
}
