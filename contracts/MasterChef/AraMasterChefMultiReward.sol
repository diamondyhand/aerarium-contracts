// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

error InsufficientBalance();
error UnableToSendValue();
error NonContractCall();
error ReentrantCall();
error ApproveError(string message);
error OptionalReturn(string message);
error NotOwner();
error ZeroAddress();
error BEP20InsufficientAllowance();
error BEP20AllowanceBelowZero();
error TransferError(string message);
error BurnError(string message);
error MintError(string message);
error BoringERC20TransferFailed();
error BoringERC20TransferFromfailed();
error InvalidDepositFeeBasisPoints();
error WithdrawNotGood();
error InsufficientRewardTokens();
error NotDevAddr();
error WrongBalance();
error WrongLpToken();
error DifferentBalance();
error NotZeroBalance();
error ForbiddenSetFeeAddr();
error InvalidRewardPerBlock();

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and make it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        if(_status == _ENTERED) {
            revert ReentrantCall();
        }

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}

interface IBEP20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the token decimals.
     */
    function decimals() external view returns (uint8);

    /**
     * @dev Returns the token symbol.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the token name.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the bep token owner.
     */
    function getOwner() external view returns (address);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(
        address _owner,
        address spender
    ) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        if(address(this).balance < amount) {
            revert InsufficientBalance();
        }

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{value: amount}("");
        if(!success) {
            revert UnableToSendValue();
        }
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain`call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(
        address target,
        bytes memory data
    ) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return
            functionCallWithValue(
                target,
                data,
                value,
                "Address: low-level call with value failed"
            );
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        if(address(this).balance < value) {
           revert InsufficientBalance();
        }
        if(!isContract(target)) {
            revert NonContractCall();
        }

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{value: value}(
            data
        );
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(
        address target,
        bytes memory data
    ) internal view returns (bytes memory) {
        return
            functionStaticCall(
                target,
                data,
                "Address: low-level static call failed"
            );
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        if(!isContract(target)) {
            revert NonContractCall();
        }

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) private pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}

library SafeBEP20 {
    using Address for address;

    function safeTransfer(IBEP20 token, address to, uint256 value) internal {
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transfer.selector, to, value)
        );
    }

    function safeTransferFrom(
        IBEP20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transferFrom.selector, from, to, value)
        );
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IBEP20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(
        IBEP20 token,
        address spender,
        uint256 value
    ) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        if((value > 0) && (token.allowance(address(this), spender) > 0))
        {
            revert ApproveError("SafeBEP20: approve from non-zero to non-zero allowance");
        }
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.approve.selector, spender, value)
        );
    }

    function safeIncreaseAllowance(
        IBEP20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + (
            value
        );
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(
                token.approve.selector,
                spender,
                newAllowance
            )
        );
    }

    function safeDecreaseAllowance(
        IBEP20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 oldAllowance = token.allowance(address(this), spender);
        if(oldAllowance < value) {
            revert ApproveError("SafeBEP20: decreased allowance below zero");
        }
        uint256 newAllowance = oldAllowance - value;
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(
                token.approve.selector,
                spender,
                newAllowance
            )
        );
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IBEP20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(
            data,
            "SafeBEP20: low-level call failed"
        );
        if(
            returndata.length > 0 && !abi.decode(returndata, (bool))
        ) {
            revert OptionalReturn("SafeBEP20: operation did not succeed");
        }
    }
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return payable(msg.sender);
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        if(owner() != _msgSender()){
            revert NotOwner();
        }
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if(newOwner == address(0)) {
            revert ZeroAddress();
        }
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract BEP20 is Context, IBEP20, Ownable {

    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    /**
     * @dev Sets the values for {name} and {symbol}, initializes {decimals} with
     * a default value of 18.
     *
     * To select a different value for {decimals}, use {_setupDecimals}.
     *
     * All three of these values are immutable: they can only be set once during
     * construction.
     */
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = 18;
    }

    /**
     * @dev Returns the bep token owner.
     */
    function getOwner() external view override returns (address) {
        return owner();
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     */
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /**
     * @dev See {BEP20-totalSupply}.
     */
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {BEP20-balanceOf}.
     */
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {BEP20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev See {BEP20-allowance}.
     */
    function allowance(
        address owner,
        address spender
    ) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {BEP20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(
        address spender,
        uint256 amount
    ) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev See {BEP20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {BEP20};
     *
     * Requirements:
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for `sender`'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        if(_allowances[sender][_msgSender()] < amount){
            revert BEP20InsufficientAllowance(); 
        }
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()] - amount
        );
        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {BEP20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(
        address spender,
        uint256 addedValue
    ) public returns (bool) {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender] + (addedValue)
        );
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {BEP20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(
        address spender,
        uint256 subtractedValue
    ) public returns (bool) {
        if(_allowances[_msgSender()][spender] < subtractedValue){
            revert BEP20AllowanceBelowZero();
        }
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender] - subtractedValue
        );
        return true;
    }

    /**
     * @dev Creates `amount` tokens and assigns them to `msg.sender`, increasing
     * the total supply.
     *
     * Requirements
     *
     * - `msg.sender` must be the token owner
     */
    function mint(uint256 amount) public onlyOwner returns (bool) {
        _mint(_msgSender(), amount);
        return true;
    }

    /**
     * @dev Moves tokens `amount` from `sender` to `recipient`.
     *
     * This is internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        if(sender == address(0)){
            revert TransferError("BEP20: transfer from the zero address");
        }
        if(recipient == address(0)){
            revert TransferError("BEP20: transfer to the zero address");
        }
        if(_balances[sender] < amount){
            revert TransferError("BEP20: transfer amount exceeds balance");
        }
        _balances[sender] = _balances[sender] - amount;
        _balances[recipient] = _balances[recipient] + (amount);
        emit Transfer(sender, recipient, amount);
    }


    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements
     *
     * - `to` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal {
        if(account == address(0)) {
            revert MintError("BEP20: mint to the zero address");
        }

        _totalSupply = _totalSupply + (amount);
        _balances[account] = _balances[account] + (amount);
        emit Transfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal {
        if(account == address(0)) {
            revert BurnError("BEP20: burn from the zero address");
        }
        if(_balances[account] < amount){
            revert BurnError("BEP20: burn amount exceeds balance");
        }
        _balances[account] = _balances[account] - amount;
        _totalSupply = _totalSupply - (amount);
        emit Transfer(account, address(0), amount);
    }
    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner`s tokens.
     *
     * This is internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(address owner, address spender, uint256 amount) internal {
        if(owner == address(0)) {
            revert ApproveError("BEP20: approve from the zero address");
        }
        if(spender == address(0)) {
            revert ApproveError("BEP20: approve to the zero address");
        }

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`.`amount` is then deducted
     * from the caller's allowance.
     *
     * See {_burn} and {_approve}.
     */
    function _burnFrom(address account, uint256 amount) internal {
        if(_allowances[account][_msgSender()] < amount){
            revert BurnError("BEP20: burn amount exceeds balance");
        }
        _burn(account, amount);
        _approve(
            account,
            _msgSender(),
            _allowances[account][_msgSender()] - amount
        );
    }
}

interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

library BoringERC20 {
    function safeSymbol(IERC20 token) internal view returns (string memory) {
        (bool success, bytes memory data) = address(token).staticcall(
            abi.encodeWithSelector(0x95d89b41)
        );
        return success && data.length > 0 ? abi.decode(data, (string)) : "???";
    }

    function safeName(IERC20 token) internal view returns (string memory) {
        (bool success, bytes memory data) = address(token).staticcall(
            abi.encodeWithSelector(0x06fdde03)
        );
        return success && data.length > 0 ? abi.decode(data, (string)) : "???";
    }

    function safeDecimals(IERC20 token) internal view returns (uint8) {
        (bool success, bytes memory data) = address(token).staticcall(
            abi.encodeWithSelector(0x313ce567)
        );
        return success && data.length == 32 ? abi.decode(data, (uint8)) : 18;
    }

    function safeTransfer(IERC20 token, address to, uint256 amount) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(0xa9059cbb, to, amount)
        );
        if(!success || !(data.length == 0 || abi.decode(data, (bool)))){
            revert BoringERC20TransferFailed();
        }
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 amount
    ) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(0x23b872dd, from, to, amount)
        );
        if(!success || !(data.length == 0 || abi.decode(data, (bool)))){
            revert BoringERC20TransferFromfailed();
        }
    }
}

interface IStrategy {
    function rewards() external view returns (address);

    function gauge() external view returns (address);

    function want() external view returns (address);

    function timelock() external view returns (address);

    function deposit() external;

    function withdrawForSwap(uint256) external returns (uint256);

    function withdraw(address) external returns (uint256);

    function withdraw(uint256) external returns (uint256);

    function withdrawTokens(uint256) external returns (uint256);

    function skim() external;

    function withdrawAll() external returns (uint256);

    function balanceOf() external view returns (uint256);

    function balanceOfWant() external view returns (uint256);

    function getHarvestable() external view returns (uint256);

    function harvest(uint256[] memory pids) external;

    function setTimelock(address) external;

    function setController(address _controller) external;

    function execute(
        address _target,
        bytes calldata _data
    ) external payable returns (bytes memory response);

    function execute(
        bytes calldata _data
    ) external payable returns (bytes memory response);
}

contract IMasterChef {
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. Reward tokens to distribute per block.
        uint256 lastRewardBlock; // Last block number that reward token distribution occurs.
        uint256 accRewardTokenPerShare; // Accumulated reward tokens per share, times 1e12. See below.
    }

    // Info of each user that stakes LP tokens.
    mapping(uint256 => PoolInfo) public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // Deposit LP tokens to MasterChef.
    function deposit(uint256 _pid, uint256 _amount) external {}

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external {}
}

pragma solidity 0.8.18;
pragma experimental ABIEncoderV2;

contract AraMasterChefMultiReward is Ownable, ReentrancyGuard {
    using SafeBEP20 for IBEP20;
    using BoringERC20 for IERC20;

    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        mapping(address => uint256) rewardDebt; // Reward debt for each token.
    }

    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. Rewards to distribute per block.
        uint256 lastRewardBlock; // Last block number that rewards distribution occurs.
        uint256 totalRewardDebt; // The total reward debt of all users in the pool.
        address[] rewardTokens; // Array of reward tokens.
        mapping(address => uint256) accRewardPerShare; // Accumulated rewards per share, times 1e12, for each token.
        uint16 depositFeeBP; // Deposit fee in basis points
    }

    // Bonus multiplier for early ara makers.
    uint256 public BONUS_MULTIPLIER = 1;
    // Deposit Fee address
    address public feeAddress;

    mapping(address => uint256) public rewardPerBlock;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    /// @notice Address of each `IStrategy`.
    IStrategy[] public strategies;
    /// @notice Address of the LP token for each MCV2 pool.
    IERC20[] public lpToken;

    event AddPool(
        uint256 indexed pid,
        uint256 allocPoint,
        address indexed lpToken,
        address[] rewardTokens
    );
    event SetPool(
        uint256 indexed pid,
        uint256 allocPoint,
        address[] rewardTokens
    );
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    event AddReward(
        uint256 indexed pid,
        address indexed rewardToken,
        uint256 rewardPerBlock
    );
    event UpdateReward(
        uint256 indexed pid,
        address indexed rewardToken,
        uint256 rewardPerBlock
    );
    event SetFeeAddress(
        address indexed feeAddress
    );
    event SetMultiplier(
        uint256 multiplier
    );

    error InvalidPoolId();
    error ZeroAddress();
    error InvalidDepositFeeBasisPoints();
    error InvalidRewardPerBlock();
    error WithdrawNotGood();
    error NotEnoughRewardBalance();

    constructor(address _feeAddress) {
        require(_feeAddress != address(0), "ZERO_ADDRESS");
        feeAddress = _feeAddress;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        uint16 _depositFeeBP,
        IStrategy _strategy,
        bool _withUpdate,
        address[] memory _rewardTokens
    ) external onlyOwner {
        require(address(_lpToken) != address(0), "ZERO_ADDRESS");
        require(address(_strategy) != address(0), "ZERO_ADDRESS");
        require(_depositFeeBP <= 10000, "InvalidDepositFeeBasisPoints");
        for (uint256 i = 0; i < _rewardTokens.length; i++) {
            require(_rewardTokens[i] != address(0), "ZERO_ADDRESS");
        }
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.timestamp;
        totalAllocPoint = totalAllocPoint + _allocPoint;
        strategies.push(_strategy);
        lpToken.push(IERC20(_lpToken));

        // Push an empty PoolInfo to poolInfo
        poolInfo.push(PoolInfo({
            lpToken: IERC20(address(0)),
            allocPoint: 0,
            lastRewardBlock: 0,
            totalRewardDebt: 0,
            rewardTokens: new address[](0),
            depositFeeBP: 0
        }));

        uint poolId = poolInfo.length - 1;
        PoolInfo storage newPool = poolInfo[poolId];
        newPool.lpToken = _lpToken;
        newPool.allocPoint = _allocPoint;
        newPool.lastRewardBlock = lastRewardBlock;
        newPool.totalRewardDebt = 0;
        newPool.rewardTokens = _rewardTokens;
        newPool.depositFeeBP = _depositFeeBP;
        for (uint256 i = 0; i < _rewardTokens.length; i++) {
            newPool.accRewardPerShare[_rewardTokens[i]] = 0;
        }

        emit AddPool(
            poolInfo.length -  1,
            _allocPoint,
            address(_lpToken),
            _rewardTokens
        );
    }

    function set(
        uint256 _pid,
        uint256 _allocPoint,
        uint16 _depositFeeBP,
        IStrategy _strategy,
        bool _withUpdate,
        address[] memory _rewardTokens
    ) external onlyOwner {
        require(_pid < poolInfo.length, "InvalidPoolId");
        require(_depositFeeBP <= 10000, "InvalidDepositFeeBasisPoints");
        for (uint256 i = 0; i < _rewardTokens.length; i++) {
            require(_rewardTokens[i] != address(0), "ZERO_ADDRESS");
        }

        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].rewardTokens = _rewardTokens;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;

        if (address(strategies[_pid]) != address(_strategy)) {
            if (address(strategies[_pid]) != address(0)) {
                _withdrawAllFromStrategy(_pid, strategies[_pid]);
            }
            if (address(_strategy) != address(0)) {
                _depositAllToStrategy(_pid, _strategy);
            }
            strategies[_pid] = _strategy;
        }

        emit SetPool(_pid, _allocPoint, _rewardTokens);
    }

    // Add a new reward token to an existing pool. Can only be called by the owner.
    function addReward(
        uint256 _pid,
        address _rewardToken,
        uint256 _rewardPerBlock
    ) external onlyOwner {
        require(_rewardToken != address(0), "ZERO_ADDRESS");
        require(_rewardPerBlock > 0, "InvalidRewardPerBlock");

        massUpdatePools();
        poolInfo[_pid].rewardTokens.push(_rewardToken);
        poolInfo[_pid].accRewardPerShare[_rewardToken] = 0;
        rewardPerBlock[_rewardToken] = _rewardPerBlock;
        emit AddReward(_pid, _rewardToken, _rewardPerBlock);
    }

    function updateReward(
        uint256 _pid,
        address _rewardToken,
        uint256 _rewardPerBlock
    ) external onlyOwner {
        require(_rewardToken != address(0), "ZERO_ADDRESS");
        require(_rewardPerBlock > 0, "InvalidRewardPerBlock");

        massUpdatePools();
        poolInfo[_pid].accRewardPerShare[_rewardToken] = _rewardPerBlock;

        emit UpdateReward(_pid, _rewardToken, _rewardPerBlock);
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(
        uint256 _from,
        uint256 _to
    ) public view returns (uint256) {
        return (_to - _from) * (BONUS_MULTIPLIER);
    }

    function setMultiplier(uint256 _BONUS_MULTIPLIER) public onlyOwner {
        BONUS_MULTIPLIER = _BONUS_MULTIPLIER;
        emit SetMultiplier(_BONUS_MULTIPLIER);
    }

    function pendingReward(
        uint256 _pid,
        address _user,
        address _rewardToken
    ) external view returns (uint256) {
        require(_pid < poolInfo.length, "InvalidPoolId");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare[_rewardToken];
        uint256 lpSupply;
        if (address(strategies[_pid]) != address(0)) {
            lpSupply = pool.lpToken.balanceOf(address(this)) + (
                strategies[_pid].balanceOf()
            );
        } else {
            lpSupply = pool.lpToken.balanceOf(address(this));
        }
        if (block.timestamp > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardBlock,
                block.timestamp
            );
            uint256 reward = multiplier
                * rewardPerBlock[_rewardToken]
                * pool.allocPoint
                / totalAllocPoint;
            accRewardPerShare = accRewardPerShare + (
                reward * (1e12) / lpSupply
            );
        }
        return user.amount * accRewardPerShare / (1e12) - user.rewardDebt[_rewardToken];
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function updatePool(uint256 _pid) public {
        require(_pid < poolInfo.length, "InvalidPoolId");
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply;
        if (address(strategies[_pid]) != address(0)) {
            lpSupply = pool.lpToken.balanceOf(address(this)) + (
                strategies[_pid].balanceOf()
            );
        } else {
            lpSupply = pool.lpToken.balanceOf(address(this));
        }
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.timestamp;
            return;
        }
        for (uint256 i = 0; i < pool.rewardTokens.length; i++) {
            address rewardToken = pool.rewardTokens[i];
            uint256 multiplier = getMultiplier(
                pool.lastRewardBlock,
                block.timestamp
            );
            uint256 reward = multiplier
                * rewardPerBlock[rewardToken]
                * pool.allocPoint
                / totalAllocPoint;
            pool.accRewardPerShare[rewardToken] = pool
                .accRewardPerShare[rewardToken]
                + (reward * (1e12) / lpSupply);
        }
        pool.lastRewardBlock = block.timestamp;
    }

    function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
        require(_pid < poolInfo.length, "InvalidPoolId");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            for (uint256 i = 0; i < pool.rewardTokens.length; i++) {
                address rewardToken = pool.rewardTokens[i];
                uint256 pending = user.amount * pool.accRewardPerShare[rewardToken] / (1e12) - user.rewardDebt[rewardToken];
                if (pending > 0) {
                    safeRewardTransfer(rewardToken, msg.sender, pending);
                }
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            if (pool.depositFeeBP > 0) {
                uint256 depositFee = _amount * pool.depositFeeBP / 10000;
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount + (_amount) -  (depositFee);
            } else {
                user.amount = user.amount + (_amount);
            }
            IStrategy _strategy = strategies[_pid];
            if (address(_strategy) != address(0)) {
                uint256 _amount1 = pool.lpToken.balanceOf(address(this));
                lpToken[_pid].safeTransfer(address(_strategy), _amount1);
                _strategy.deposit();
            }
        }
        for (uint256 i = 0; i < pool.rewardTokens.length; i++) {
            address rewardToken = pool.rewardTokens[i];
            user.rewardDebt[rewardToken] = user.amount * pool.accRewardPerShare[rewardToken] / (1e12);
        }
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MultiRewardMasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external {
        require(_pid < poolInfo.length, "InvalidPoolId");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "WithdrawNotGood");
        uint256 balance = pool.lpToken.balanceOf(address(this));
        IStrategy strategy = strategies[_pid];
        updatePool(_pid);
        for (uint256 i = 0; i < pool.rewardTokens.length; i++) {
            address rewardToken = pool.rewardTokens[i];
            uint256 pending = user.amount * pool.accRewardPerShare[rewardToken] / (1e12) - user.rewardDebt[rewardToken];
            if (pending > 0) {
                safeRewardTransfer(rewardToken, msg.sender, pending);
            }
        }
        if (_amount > 0) {
            user.amount = user.amount - (_amount);
            if (_amount > balance) {
                uint256 missing = _amount - (balance);
                uint256 withdrawn = strategy.withdrawTokens(missing);
                _amount = balance + (withdrawn);
            }
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        for (uint256 i = 0; i < pool.rewardTokens.length; i++) {
            address rewardToken = pool.rewardTokens[i];
            user.rewardDebt[rewardToken] = user.amount * pool.accRewardPerShare[rewardToken] / (1e12);
        }
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external {
        require(_pid < poolInfo.length, "InvalidPoolId");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(
            address(msg.sender),
            user.amount
        );
        user.amount = 0;
        for (uint256 i = 0; i < pool.rewardTokens.length; i++) {
            address rewardToken = pool.rewardTokens[i];
            user.rewardDebt[rewardToken] = 0;
        }
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
    }

    // Safe reward transfer function, just in case if rounding error causes pool to not have enough REWARDs.
    function safeRewardTransfer(
        address _rewardToken,
        address _to,
        uint256 _amount
    ) internal {
        uint256 rewardBal = IERC20(_rewardToken).balanceOf(address(this));
        require(_amount <= rewardBal, "NotEnoughRewardBalance");
        IERC20(_rewardToken).transfer(_to, _amount);
    }
    
    function _withdrawAllFromStrategy(
        uint256 _pid,
        IStrategy _strategy
    ) internal {
        _strategy.withdrawAll();
        uint256 _amount = poolInfo[_pid].lpToken.balanceOf(address(this));
        userInfo[_pid][address(_strategy)] = UserInfo({
            amount: 0,
            rewardDebt: userInfo[_pid][address(_strategy)].rewardDebt
        });
        emit Withdraw(address(_strategy), _pid, _amount);
    }

    function _depositAllToStrategy(
        uint256 _pid,
        IStrategy _strategy
    ) internal {
        uint256 _amount = poolInfo[_pid].lpToken.balanceOf(address(this));
        poolInfo[_pid].lpToken.safeTransfer(
            address(_strategy),
            _amount
        );
        _strategy.deposit();
        userInfo[_pid][address(_strategy)] = UserInfo({
            amount: _amount,
            rewardDebt: userInfo[_pid][address(_strategy)].rewardDebt
        });
        emit Deposit(address(_strategy), _pid, _amount);
    }

    function setFeeAddress(address _feeAddress) external onlyOwner {
        require(_feeAddress != address(0), "ZERO_ADDRESS");
        feeAddress = _feeAddress;
        emit SetFeeAddress(_feeAddress);
    }
}


