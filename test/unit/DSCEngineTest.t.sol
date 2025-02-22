// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDecentralizedStableCoin} from "../../script/DeployDecentralizedStableCoin.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address ethUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        DeployDecentralizedStableCoin deploy = new DeployDecentralizedStableCoin();
        (dscEngine, dsc, config) = deploy.run();
        (ethUsdPriceFeed,, weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

		function testRevertIfTheTokenLengthDoesntMatchThePriceFeeds() public {
			address[] memory tokens = new address[](2);	
			address[] memory priceFeeds = new address[](1);

			vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedsAddressesMustBeTheSameLength.selector);
			new DSCEngine(tokens, priceFeeds, address(dsc));
		}

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedAmount = 30000e18;
        uint256 actualUsd = dscEngine.getTokenUsdValue(weth, ethAmount);

        assertEq(expectedAmount, actualUsd);
    }

		function testGetTokeAmountFromUsd() public view {
			uint256 usAmount = 100 ether;
			uint256 expectedWeth = 0.05 ether;
			uint256 actualWeth = dscEngine.getTokenAmountFromUsd(weth, usAmount);
			assertEq(expectedWeth, actualWeth);
		}

    function testRvertsIfCollateralZero() public {
        vm.expectRevert(DSCEngine.DSCEngine__MystBeMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

		function testRevertWithUnapprovedCollateral() public {
			vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
			dscEngine.depositCollateral(makeAddr("unapproved"), AMOUNT_COLLATERAL);
			vm.stopPrank();
		}

		modifier depositedCollateral() {
			vm.startPrank(USER);
			ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
			dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
			vm.stopPrank();
			_;
		}

		function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
			(uint256 totalDscMinted, uint256 collateralValueInUd) = dscEngine.getAccountInformation(USER);
			uint256 expectedTotalDscMinted = 0;
			uint256 expectedCollateralValueInUsd = dscEngine.getTokenUsdValue(weth, AMOUNT_COLLATERAL);

			assertEq(expectedTotalDscMinted, totalDscMinted);
			assertEq(expectedCollateralValueInUsd, collateralValueInUd);
		}
}

