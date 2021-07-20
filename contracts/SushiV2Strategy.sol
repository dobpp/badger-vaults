// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {BaseStrategyUpgradeable, StrategyParams} from "./BaseStrategyUpgradeable.sol";
import {SafeERC20, SafeMath, IERC20, Address} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {ISushiChef} from "../interfaces/sushi/ISushichef.sol";
import {IUniswapRouterV2} from "../interfaces/uniswap/IUniswapRouterV2.sol";
import "../interfaces/sushi/IxSushi.sol";

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

    address public WETH;
    address public badgerTree;

    ISushiChef public MASTERCHEF;

    IUniswapRouterV2 public ROUTER;

    function initialize(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper
    ) external {
        BaseStrategyUpgradeable.initialize(
            _vault, 
            _strategist,
            _rewards,
            _keeper
        );
        MASTERCHEF = ISushiChef(chef);
        want.approve(chef, uint256(-1));
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
        MASTERCHEF.harvest(pid, address(this));
        uint256 toSwap = reward.balanceOf(address(this));

        // TODO: Put sushi to badgerTree to distribute
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        uint256 _beforeLp = want.balanceOf(address(this));

        // Note: Deposit of zero harvests rewards balance, but go ahead and deposit idle want if we have it
        MASTERCHEF.deposit(pid, _beforeLp);
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
            MASTERCHEF.withdraw(pid, _toWithdraw);
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
    function _swapToWant(uint256 toSwap) internal returns (uint256) {
        uint256 startingWantBalance = want.balanceOf(address(this));

        address[] memory path = new address[](3);
        path[0] = address(sushi);
        path[1] = WETH;
        path[2] = address(want);

        reward.approve(address(ROUTER), toSwap);

        // Warning, no slippage checks, can be frontrun
        ROUTER.swapExactTokensForTokens(toSwap, 0, path, address(this), now);

        return want.balanceOf(address(this)).sub(startingWantBalance);
    }
}