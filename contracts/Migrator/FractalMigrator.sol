pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TokenSwap {
    address private _owner;
    IERC721 private _nft;
    IERC20 private _token;

    constructor(IERC721 nftAddress, IERC20 tokenAddress) {
        _owner = msg.sender;
        _nft = nftAddress;
        _token = tokenAddress;
    }

    function swap(address recipient, uint256 tokenId, uint256 amount) public {
        require(msg.sender == _owner, "Only owner can call this function");
        require(_nft.ownerOf(tokenId) == address(this), "NFT not transferred to contract");
        require(_token.balanceOf(address(this)) >= amount, "Insufficient balance");

        _nft.safeTransferFrom(address(this), recipient, tokenId);
        _token.transfer(recipient, amount);
    }

    function withdrawNFT(uint256 tokenId) public {
        require(msg.sender == _owner, "Only owner can call this function");
        require(_nft.ownerOf(tokenId) == address(this), "NFT not transferred to contract");

        _nft.safeTransferFrom(address(this), msg.sender, tokenId);
    }

    function withdrawToken() public {
        require(msg.sender == _owner, "Only owner can call this function");
        require(_token.balanceOf(address(this)) > 0, "Insufficient balance");

        _token.transfer(msg.sender, _token.balanceOf(address(this)));
    }
}
