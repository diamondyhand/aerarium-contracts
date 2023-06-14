// SPDX-License-Identifier: MIT

/**
 * @dev Interface of the MasterHummusV2
 */
interface IMasterHummusV2 {
    function poolLength() external view returns (uint256);

    function userInfo(
        uint256,
        address
    )
        external
        view
        returns (uint256 amount, uint256 rewardDebt, uint256 factor);

    function pendingTokens(
        uint256 _pid,
        address _user
    )
        external
        view
        returns (
            uint256 pendingHum,
            address bonusTokenAddress,
            string memory bonusTokenSymbol,
            uint256 pendingBonusToken
        );

    function rewarderBonusTokenInfo(
        uint256 _pid
    )
        external
        view
        returns (address bonusTokenAddress, string memory bonusTokenSymbol);

    function massUpdatePools() external;

    function updatePool(uint256 _pid) external;

    function poolAdjustFactor(uint256 pid) external view returns (uint256);

    function deposit(
        uint256 _pid,
        uint256 _amount
    ) external returns (uint256, uint256);

    function multiClaim(
        uint256[] calldata _pids
    ) external returns (uint256, uint256[] memory, uint256[] memory);

    function withdraw(
        uint256 _pid,
        uint256 _amount
    ) external returns (uint256, uint256);

    function emergencyWithdraw(uint256 _pid) external;

    function migrate(uint256[] calldata _pids) external;

    function depositFor(uint256 _pid, uint256 _amount, address _user) external;

    function updateFactor(address _user, uint256 _newVeHumBalance) external;
}

pragma solidity 0.8.18;

/**
 * @dev Collection of functions related to the address type
 */
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
        require(
            address(this).balance >= amount,
            "Address: insufficient balance"
        );

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{value: amount}("");
        require(
            success,
            "Address: unable to send value, recipient may have reverted"
        );
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
        require(
            address(this).balance >= value,
            "Address: insufficient balance for call"
        );
        require(isContract(target), "Address: call to non-contract");

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
        require(isContract(target), "Address: static call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(
        address target,
        bytes memory data
    ) internal returns (bytes memory) {
        return
            functionDelegateCall(
                target,
                data,
                "Address: low-level delegate call failed"
            );
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.delegatecall(data);
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


pragma solidity 0.8.18;

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transfer.selector, to, value)
        );
    }

    function safeTransferFrom(
        IERC20 token,
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
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.approve.selector, spender, value)
        );
    }

    function safeIncreaseAllowance(
        IERC20 token,
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
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        require(token.allowance(address(this), spender) >= value, "SafeERC20: decreased allowance below zero");
        uint256 newAllowance = token.allowance(address(this), spender) - value;
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
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(
            data,
            "SafeERC20: low-level call failed"
        );
        if (returndata.length > 0) {
            // Return data is optional
            // solhint-disable-next-line max-line-length
            require(
                abi.decode(returndata, (bool)),
                "SafeERC20: ERC20 operation did not succeed"
            );
        }
    }
}

pragma solidity 0.8.18;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
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

pragma solidity 0.8.18;

interface ILiquidDepositor {
    function treasury() external view returns (address);
}

pragma solidity 0.8.18;

interface IMasterChef {
    function BONUS_MULTIPLIER() external view returns (uint256);

    function add(
        uint256 _allocPoint,
        address _lpToken,
        bool _withUpdate
    ) external;

    function bonusEndBlock() external view returns (uint256);

    function deposit(uint256 _pid, uint256 _amount) external;

    function dev(address _devaddr) external;

    function devFundDivRate() external view returns (uint256);

    function devaddr() external view returns (address);

    function emergencyWithdraw(uint256 _pid) external;

    function getMultiplier(
        uint256 _from,
        uint256 _to
    ) external view returns (uint256);

    function massUpdatePools() external;

    function owner() external view returns (address);

    function pendingPickle(
        uint256 _pid,
        address _user
    ) external view returns (uint256);

    function pendingReward(
        uint256 _pid,
        address _user
    ) external view returns (uint256);

    function pending(
        uint256 _pid,
        address _user
    ) external view returns (uint256);

    function pickle() external view returns (address);

    function picklePerBlock() external view returns (uint256);

    function poolInfo(
        uint256
    )
        external
        view
        returns (
            address lpToken,
            uint256 allocPoint,
            uint256 lastRewardBlock,
            uint256 accPicklePerShare
        );

    function poolLength() external view returns (uint256);

    function renounceOwnership() external;

    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) external;

    function setBonusEndBlock(uint256 _bonusEndBlock) external;

    function setDevFundDivRate(uint256 _devFundDivRate) external;

    function setPicklePerBlock(uint256 _picklePerBlock) external;

    function startBlock() external view returns (uint256);

    function totalAllocPoint() external view returns (uint256);

    function transferOwnership(address newOwner) external;

    function updatePool(uint256 _pid) external;

    function userInfo(
        uint256,
        address
    ) external view returns (uint256 amount, uint256 rewardDebt);

    function withdraw(uint256 _pid, uint256 _amount) external;
}

pragma solidity 0.8.18;

abstract contract StrategyBase {
    using SafeERC20 for IERC20;
    using Address for address;

    // Tokens
    address public want;

    // User accounts
    address public governance;
    address public depositor;

    mapping(address => bool) public harvesters;

    constructor(address _want, address _depositor) {
        require(_want != address(0));
        require(_depositor != address(0));

        want = _want;
        depositor = _depositor;
        governance = msg.sender;
    }

    // **** Modifiers **** //

    modifier onlyBenevolent() {
        require(
            harvesters[msg.sender] ||
                msg.sender == governance ||
                msg.sender == depositor
        );
        _;
    }

    // **** Views **** //

    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    function balanceOfPool() public view virtual returns (uint256);

    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + (balanceOfPool());
    }

    // **** Setters **** //

    function whitelistHarvesters(address[] calldata _harvesters) external {
        require(msg.sender == governance, "not authorized");
        for (uint i = 0; i < _harvesters.length; i++) {
            harvesters[_harvesters[i]] = true;
        }
    }

    function revokeHarvesters(address[] calldata _harvesters) external {
        require(msg.sender == governance, "not authorized");

        for (uint i = 0; i < _harvesters.length; i++) {
            harvesters[_harvesters[i]] = false;
        }
    }

    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setDepositor(address _depositor) external {
        require(msg.sender == governance, "!governance");
        depositor = _depositor;
    }

    // **** State mutations **** //
    function deposit() public virtual;

    // Controller only function for creating additional rewards from dust
    function withdrawAssets(
        IERC20 _asset
    ) external onlyBenevolent returns (uint256 balance) {
        require(want != address(_asset), "want");
        balance = _asset.balanceOf(address(this));
        _asset.safeTransfer(depositor, balance);
    }

    // Withdraw partial funds
    function withdrawTokens(uint256 _amount) external returns (uint256) {
        require(msg.sender == depositor, "!depositor");
        uint256 _balance = IERC20(want).balanceOf(address(this));
        if (_balance < _amount) {
            _amount = _withdrawSome(_amount - (_balance));
            _amount = _amount + (_balance);
        }

        IERC20(want).transfer(depositor, _amount);

        return _amount;
    }

    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() external returns (uint256 balance) {
        require(msg.sender == governance, "!governance");
        _withdrawAll();

        balance = IERC20(want).balanceOf(address(this));

        IERC20(want).safeTransfer(depositor, balance);
    }

    function _withdrawAll() internal {
        _withdrawSome(balanceOfPool());
    }

    function _withdrawSome(uint256 _amount) internal virtual returns (uint256);

    function harvest(uint256[] memory pids) public virtual;
}

pragma solidity 0.8.18;

abstract contract StrategyGeneralMasterChefBase is StrategyBase {
    // Token addresses
    address public masterchef;
    address public rewardToken;

    address public bonusToken;
    address public devAddress;

    uint256 public poolId;

    constructor(
        address _rewardToken,
        address _masterchef,
        uint256 _poolId,
        address _lp,
        address _depositor,
        address _bonusToken,
        address _devAddress
    )  StrategyBase(_lp, _depositor) {
        poolId = _poolId;
        rewardToken = _rewardToken;
        masterchef = _masterchef;
        bonusToken = _bonusToken;
        devAddress = _devAddress;
    }

    function balanceOfPool() public view override returns (uint256) {
        (uint256 amount, ) = IMasterChef(masterchef).userInfo(
            poolId,
            address(this)
        );
        return amount;
    }

    function getHarvestable() external view virtual returns (uint256) {
        uint256 _pendingReward = IMasterChef(masterchef).pendingReward(
            poolId,
            address(this)
        );
        return _pendingReward;
    }

    // **** Setters ****

    function deposit() public override {
        uint256 _want = IERC20(want).balanceOf(address(this));
        if (_want > 0) {
            IERC20(want).approve(
                masterchef,
                115792089237316195423570985008687907853269984665640564039457584007913129639935
            );
            IMasterHummusV2(masterchef).deposit(poolId, _want);
        }
    }

    function _withdrawSome(
        uint256 _amount
    ) internal override returns (uint256) {
        IMasterHummusV2(masterchef).withdraw(poolId, _amount);
        return _amount;
    }

    // **** State Mutations ****
    function harvest(uint256[] memory pids) public override onlyBenevolent {
        IMasterHummusV2(masterchef).multiClaim(pids);
        uint256 _rewardBalance = IERC20(rewardToken).balanceOf(address(this));
        IERC20(rewardToken).transfer(devAddress, _rewardBalance);
    }

    function harvestNativeToken() public payable {
        uint256 amount = msg.value;
        require(amount > 0, "Amount should be greater than 0");
        payable(msg.sender).transfer(amount);
    }

    receive() external payable {
        // code to handle incoming native tokens
        // you can add any additional logic here based on your requirements
    }
}

pragma solidity 0.8.18;

contract HummusV3Strategy is StrategyGeneralMasterChefBase {
    // Token addresses
    address public hum = 0x4aAC94985cD83be30164DfE7e9AF7C054D7d2121;
    address public masterChef = 0x9c3cdE31f153FBCE9Bbee1fa9a6596AbE9BA40fC;

    constructor(
        address depositor,
        address lp,
        uint256 pid,
        address bonusToken,
        address devAddress
    )
        
        StrategyGeneralMasterChefBase(
            hum,
            masterChef,
            pid, // pool id
            lp,
            depositor,
            bonusToken,
            devAddress
        )
    {}

    function getHarvestable() external view override returns (uint256) {
        //mudar esta shit
        (uint256 pendingHum, , , ) = IMasterHummusV2(masterchef).pendingTokens(
            poolId,
            address(this)
        );
        return pendingHum;
    }

    function getHarvestableBonusToken() external view returns (uint256) {
        //mudar esta shit
        (, , , uint256 pendingBonusToken) = IMasterHummusV2(masterchef)
            .pendingTokens(poolId, address(this));
        return pendingBonusToken;
    }
}
