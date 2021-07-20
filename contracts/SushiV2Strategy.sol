// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {BaseStrategyUpgradeable, StrategyParams} from "./BaseStrategyUpgradeable.sol";
import {SafeERC20, SafeMath, IERC20, Address} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {IMiniChefV2} from "../interfaces/sushi/ISushichef.sol";
import {IUniswapRouterV2} from "../interfaces/uniswap/IUniswapRouterV2.sol";
import "../interfaces/sushi/IRewarder.sol";

/// @author Khanh
/// @title Sushi Masterchef v2 strategy
contract Strategy is BaseStrategyUpgradeable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IERC20 public reward;
    uint256 public pid = 0;
    address public constant sushi = 0x0b3F868E0BE5597D5DB7fEB59E1CADBb0fdDa50a;
    address public constant chef = 0x0769fd68dFb93167989C6f7254cd0D766Fb2841F;
    address public constant wmatic = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;

    address public WETH;
    address public badgerTree;

    IMiniChefV2 public MASTERCHEF;

    IUniswapRouterV2 public ROUTER;

    function initialize(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper,
        uint256 _pid
    ) external {
        BaseStrategyUpgradeable.initialize(
            _vault, 
            _strategist,
            _rewards,
            _keeper
        );
        MASTERCHEF = IMiniChefV2(chef);
        want.approve(chef, uint256(-1));
        pid = _pid;
    }

    /// @notice Name of Strategy
    function name() external view override returns (string memory) {
        return "StrategySushiGeneric";
    }

    /// @notice Total want token balance
    function estimatedTotalAssets() public view override returns (uint256) {
        (uint256 staked, ) = MASTERCHEF.userInfo(pid, address(this));
        return want.balanceOf(address(this)).add(staked);
    }

    function checkPendingReward() external returns (uint256, uint256) {
        (uint256 _pendingSushi, uint256 _pendingMatic) = checkPendingRewardInternal();
        return (_pendingSushi, _pendingMatic);
    }

    function checkPendingRewardInternal() internal returns (uint256, uint256) {
        uint256 _pendingSushi = MASTERCHEF.pendingSushi(pid, address(this));
        IRewarder rewarder = MASTERCHEF.rewarder(pid);
        (, uint256[] memory _rewardAmounts) = rewarder.pendingTokens(pid, address(this), 0);

        uint256 _pendingMatic;
        if (_rewardAmounts.length > 0) {
            _pendingMatic = _rewardAmounts[0];
        }
        return (_pendingSushi, _pendingMatic);
    }

    /// @notice Harvest with profit calculation
    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        // TODO: Deal with Double Rewards
        uint256 _before = want.balanceOf(address(this));

        (uint256 pendingSushi, uint256 pendingMatic) = checkPendingRewardInternal();

        if (pendingSushi > 0) {
            MASTERCHEF.harvest(pid, address(this));
        }

        // swap wmatic to sushi
        uint256 _wmatic = IERC20(wmatic).balanceOf(address(this));
        if (_wmatic > 0 ) {
            _swapWMaticToWant(_wmatic);
        }
        
        _debtPayment = _debtOutstanding;

        if (_debtPayment > 0) {
            MASTERCHEF.withdraw(pid, _debtPayment, address(this));
        }

        _profit = want.balanceOf(address(this)).sub(_before);
        _loss = 0;
        // TODO: Put sushi to badgerTree to distribute
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        uint256 _beforeLp = want.balanceOf(address(this));

        if(_beforeLp > _debtOutstanding){
            MASTERCHEF.deposit(pid, _beforeLp.sub(_debtOutstanding), address(this));
        }

        if(_debtOutstanding > _beforeLp){
            // We need to withdraw
            MASTERCHEF.withdraw(pid, _debtOutstanding.sub(_beforeLp), address(this));
        }
        // Note: Deposit of zero harvests rewards balance, but go ahead and deposit idle want if we have it
    }

    /// @notice Withdraw amount of want token from Masterchef
    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        // Get idle want in the strategy
        uint256 _preWant = want.balanceOf(address(this));

        if (_preWant < _amountNeeded) {
            uint256 _toWithdraw = _amountNeeded.sub(_preWant);
            MASTERCHEF.withdraw(pid, _toWithdraw, address(this));
        }

        uint256 totalAssets = want.balanceOf(address(this));
        if (_amountNeeded > totalAssets) {
            _liquidatedAmount = totalAssets;
            _loss = _amountNeeded.sub(totalAssets);
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    /// @notice Withdraw all want token from Masterchef
    function liquidateAllPositions() internal override returns (uint256) {
        // This is a generalization of withdrawAll that withdraws everything for the entire strat
        (uint256 staked, ) = MASTERCHEF.userInfo(pid, address(this));

        // Withdraw all want from Chef
        MASTERCHEF.withdrawAndHarvest(pid, staked, address(this));

        return want.balanceOf(address(this));
    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary

    function prepareMigration(address _newStrategy) internal override {
        // Liquidate All positons
        liquidateAllPositions();
    }

    /// @notice protected tokens
    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](2);
        protected[0] = address(want);
        protected[1] = sushi;
        // NOTE: May need to add lpComponent anyway
        return protected;
    }

    /**
     * @notice
     *  Provide an accurate conversion from `_amtInWei` (denominated in wei)
     *  to `want` (using the native decimal characteristics of `want`).
     * @dev
     *  Care must be taken when working with decimals to assure that the conversion
     *  is compatible. As an example:
     *
     *      given 1e17 wei (0.1 ETH) as input, and want is USDC (6 decimals),
     *      with USDC/ETH = 1800, this should give back 1800000000 (180 USDC)
     *
     * @param _amtInWei The amount (in wei/1e-18 ETH) to convert to `want`
     * @return The amount in `want` of `_amtInEth` converted to `want`
     **/
    function ethToWant(uint256 _amtInWei)
        public
        view
        virtual
        override
        returns (uint256)
    {
        // TODO create an accurate price oracle
        return _amtInWei;
    }

    /// @notice swap sushi to want
    function _swapWMaticToWant(uint256 toSwap) internal returns (uint256) {
        uint256 startingWantBalance = want.balanceOf(address(this));

        address[] memory path = new address[](3);
        path[0] = wmatic;
        path[1] = WETH;
        path[2] = address(want);

        reward.approve(address(ROUTER), toSwap);

        // Warning, no slippage checks, can be frontrun
        ROUTER.swapExactTokensForTokens(toSwap, 0, path, address(this), now);

        return want.balanceOf(address(this)).sub(startingWantBalance);
    }
}