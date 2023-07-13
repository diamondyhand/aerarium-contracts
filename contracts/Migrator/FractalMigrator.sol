// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

error NotNewTokenOwner();
error NotOldTokenOwner();
error NotEnoughTokens();

interface IERC721 {
    function approve(address spender, uint256 tokenId) external returns (bool);
    function totalSupply() external view returns (uint256);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function ownerOf(uint256 tokenId) external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address from, address to, uint256 tokenId) external;
}

interface IERC721Enumerable is IERC721 {
    function totalSupply() external view returns (uint256);
    function tokenOfOwnerByIndex(
        address owner,
        uint256 index
    ) external view returns (uint256 tokenId);
    function tokenByIndex(uint256 index) external view returns (uint256);
}

contract FractalMigrator{
    IERC721 public oldToken;
    IERC721 public newToken;
    address public owner;

    // Mapping from oldTokenId to newTokenId
    mapping(uint256 => uint256) public tokenSwapMapping;

    modifier onlyOwner(bool isNew) {
        if(isNew) {
            if(owner != msg.sender){
                revert NotNewTokenOwner();
            }
        }
        else {
            if(owner != msg.sender) {
                revert NotOldTokenOwner();
            }
        }
        _;
    }

    error ZeroAddress();

    constructor(address _oldTokenAddress, address _newTokenAddress) {
        if(_oldTokenAddress == address(0) || _newTokenAddress == address(0)) {
            revert ZeroAddress();
        }
        
        oldToken = IERC721(_oldTokenAddress);
        newToken = IERC721(_newTokenAddress);
        owner = msg.sender;
    }

    function balance(uint256 _tokenId) public view returns (bool) {
        return oldToken.ownerOf(_tokenId) == msg.sender;
    }

    function swap(uint256[] memory _tokenIds) public {
        for (uint i = 0; i < _tokenIds.length; i++) {
            oldToken.transferFrom(msg.sender, address(this), _tokenIds[i]);

            // Swap with the corresponding new token
            uint256 newTokenId = tokenSwapMapping[_tokenIds[i]];
            newToken.transferFrom(address(this), msg.sender, newTokenId);
        }
    }

    function withdrawOldTokens(uint256[] memory _tokenIds) public onlyOwner(false){
        for (uint i = 0; i < _tokenIds.length; i++) {
            oldToken.transferFrom(address(this), msg.sender, _tokenIds[i]);
        }
    }

    function withdrawNewTokens(uint256[] memory _tokenIds) public onlyOwner(true){
        for (uint i = 0; i < _tokenIds.length; i++) {
            newToken.transferFrom(address(this), msg.sender, _tokenIds[i]);
        }
    }

    function depositNewTokens(uint256[] memory _tokenIds) public {
        for (uint i = 0; i < _tokenIds.length; i++) {
            newToken.transferFrom(msg.sender, address(this), _tokenIds[i]);
        }
    }

    // Function to set the swap mapping for a token
    function setTokenSwapMapping(uint256 oldTokenId, uint256 newTokenId) external onlyOwner {
        tokenSwapMapping[oldTokenId] = newTokenId;
    }
}
