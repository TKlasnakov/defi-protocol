// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { DecentralizedStableCoin } from "./DecentralizedStableCoin.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DSCEngine
 * @author Todor Klasnakov
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg.
 * The stable coin has the properties:
 *	- Exogenous Collateral: ETH & BTC
 *	- Algorithmically Stable
 *
 * @notice The contract is the core of the system. It handle all the logic for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is VERY loosely based on the MakerDao DSS (DAI) system.
 */

contract DSCEngine is ReentrancyGuard {
	error DSCEngine__MystBeMoreThanZero();
	error DSCEngine__TokenNotAllowed();
	error DSCEngine__TokenAddressesAndPriceFeedsAddressesMustBeTheSameLength();
	error DSCEngine__TransferFaild();

	mapping(address tolen => address priceFeed) private s_priceFeeds;
	mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;

	DecentralizedStableCoin private immutable i_dsc;

	event CollateralDeposited(address indexed user, address indexed token, uint256 amount);

	modifier moreThanZero(uint256 _amount) {
		if (_amount <= 0) {
			revert DSCEngine__MystBeMoreThanZero();
		}
		_;
	}

	modifier isAllowedToken(address _token) {
		if ( s_priceFeeds[_token]== address(0)) {
			revert DSCEngine__TokenNotAllowed();
		}
		_;
	}

	constructor(
		address[] memory tokenAddresses, 
		address[] memory priceFeedAddresses,
		address dscAddress
	) {

		if(tokenAddresses.length != priceFeedAddresses.length) {
			revert DSCEngine__TokenAddressesAndPriceFeedsAddressesMustBeTheSameLength();
		}

		i_dsc = DecentralizedStableCoin(dscAddress);
	}

	function depositCollateralAndMintDSC() external {
		// Deposit collateral
		// Mint DSC
	}

	/**
	 * @notice Deposit collateral to mint DSC
	 * @param _tokenCollateralAddress The address of the token to be deposited as collateral
	 * @param _amountCollateral The amount of the token to be deposited as collateral
	 */

	function depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral)
	external 
	moreThanZero(_amountCollateral) 
	isAllowedToken(_tokenCollateralAddress) 
	nonReentrant 
	{
		s_collateralDeposited[msg.sender][_tokenCollateralAddress] += _amountCollateral;
		emit CollateralDeposited(msg.sender, _tokenCollateralAddress, _amountCollateral);
		bool success = IERC20(_tokenCollateralAddress).transferFrom(msg.sender, address(this), _amountCollateral);

		if(!success) {
			revert DSCEngine__TransferFaild();
		}
	}

	function redeemCollateralForDsc() external {
		// Redeem DSC
		// Withdraw collateral
	}

	function redeemCollateral() external {

	}

	function mintDsc() external {
		// Mint DSC
	}

	function burnDsc() external {
		// Burn DSC
	}

	function liquidate() external {
		// Liquidate
	}
	
	function getHealtFactor() external view {
		// Get health factor
	}
}
