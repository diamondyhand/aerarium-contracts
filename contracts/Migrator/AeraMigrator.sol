pragma solidity ^0.8.0;

interface ERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract TokenSwap {
    ERC20 public oldToken;
    ERC20 public newToken;
    address public owner;
    uint256 public swapRatio;

    constructor(address _oldTokenAddress, address _newTokenAddress, uint256 _swapRatio) {
        oldToken = ERC20(_oldTokenAddress);
        newToken = ERC20(_newTokenAddress);
        owner = msg.sender;
        swapRatio = _swapRatio;
    }

    function swap() public {
        uint256 oldTokenAmount = oldToken.balanceOf(msg.sender);
        uint256 newTokenAmount = oldTokenAmount * swapRatio;
        require(newTokenAmount > 0, "Amount of new tokens must be greater than zero.");
        require(oldToken.transferFrom(msg.sender, address(this), oldTokenAmount), "Failed to transfer old tokens.");
        require(newToken.transfer(msg.sender, newTokenAmount), "Failed to transfer new tokens.");
    }

    function withdrawOldTokens() public {
        require(msg.sender == owner, "Only the contract owner can withdraw old tokens.");
        uint256 balance = oldToken.balanceOf(address(this));
        require(oldToken.transfer(owner, balance), "Failed to transfer old tokens.");
    }

    function withdrawNewTokens() public {
        require(msg.sender == owner, "Only the contract owner can withdraw new tokens.");
        uint256 balance = newToken.balanceOf(address(this));
        require(newToken.transfer(owner, balance), "Failed to transfer new tokens.");
    }
}
