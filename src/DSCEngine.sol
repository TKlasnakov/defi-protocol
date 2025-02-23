// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

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
    error DSCEngine__BreaksHeltFactor(uint256 userHeltFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();
		error DSCEngine__MustHaveMintedDsc();

    uint256 private constant ADDITIONAL_FEE_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUDITION_THRESHOLD = 50;
    uint256 private constant LIQUDITION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATOR_BONUS = 10;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinter) private s_amountDscMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(address indexed redeemedFrom, address redeemedTo, address indexed token, uint256 amount);

    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert DSCEngine__MystBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address _token) {
        if (s_priceFeeds[_token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedsAddressesMustBeTheSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /*
    * @param _tokenCollateralAddress - The address of the token to deposit as collateral	
    * @param _amountCollateral - The amount of collateral to deposit
    * @param _amountDscToMent - The amount of decentralized stablecoin to mint
    * @notice This function will deposit your collateral and mint DSC in one transaction
    */

    function depositCollateralAndMintDSC(
        address _tokenCollateralAddress,
        uint256 _amountCollateral,
        uint256 _amountDscToMint
    ) external {
        depositCollateral(_tokenCollateralAddress, _amountCollateral);
        mintDsc(_amountDscToMint);
    }

    /*
     * @notice Deposit collateral to mint DSC
     * @param _tokenCollateralAddress The address of the token to be deposited as collateral
     * @param _amountCollateral The amount of the token to be deposited as collateral
     */
    function depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral)
        public
        moreThanZero(_amountCollateral)
        isAllowedToken(_tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][_tokenCollateralAddress] += _amountCollateral;
        emit CollateralDeposited(msg.sender, _tokenCollateralAddress, _amountCollateral);
        bool success = IERC20(_tokenCollateralAddress).transferFrom(msg.sender, address(this), _amountCollateral);

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /*
    * @param _tokenCollateralAddress - The address of the token used for collateral
    * @param _amountCollateral - The amount of collateral to redeem
    * @param _amountToBurn - The amount of DSC to be burned
    * @notice - This function burns DSC and redeems underlying collateral in one transaction
    */
    function redeemCollateralForDsc(address _tokenCollateralAddress, uint256 _amountCollateral, uint256 _amountToBurn)
        external
    {
        burnDsc(_amountToBurn);
        redeemCollateral(_tokenCollateralAddress, _amountCollateral);
    }

    function redeemCollateral(address _tokenCollateralAddress, uint256 _amountCollateral)
        public
        moreThanZero(_amountCollateral)
    {
        _redeemCollateral(msg.sender, msg.sender, _tokenCollateralAddress, _amountCollateral);
    }

    function mintDsc(uint256 _amountDscToMint) public moreThanZero(_amountDscToMint) nonReentrant {
        s_amountDscMinted[msg.sender] += _amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, _amountDscToMint);

        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 _amount) public moreThanZero(_amount) {
        _burnDsc(_amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
    * @param _collateral - The ERC20 collateral address to liquidate from the user
    * @param _user - The user who has broken the health factor. Their heltFactor should be bellow MIN_HEALTH_FACTOR
    * @param _debtToCover - Amount of DSC you want to burn to improve the users helth factor
    */
    function liquidate(address _collateral, address _user, uint256 _debtToCover)
        external
        moreThanZero(_debtToCover)
        nonReentrant
    {
        uint256 startingUserHealtFactor = _healthFactor(_user);
        if (startingUserHealtFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(_collateral, _debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATOR_BONUS) / LIQUDITION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(_user, msg.sender, _collateral, totalCollateralToRedeem);
        _burnDsc(_debtToCover, _user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(_user);

        if (endingUserHealthFactor <= startingUserHealtFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }


    function _getAccountInformationOfTheUser(address _user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_amountDscMinted[_user];
        collateralValueInUsd = getAccountCollateralValue(_user);
    }

    function _burnDsc(uint256 _amount, address _onBehalfOf, address _dscFrom)
        private
        moreThanZero(_amount)
        nonReentrant
    {
        s_amountDscMinted[_onBehalfOf] -= _amount;
        bool success = i_dsc.transferFrom(_dscFrom, address(this), _amount);

        if (!success) {
            revert DSCEngine__TransferFailed();
        }

        i_dsc.burn(_amount);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function _redeemCollateral(address _from, address _to, address _tokenCollateralAddress, uint256 _amountCollateral)
        private
        moreThanZero(_amountCollateral)
        nonReentrant
    {
        s_collateralDeposited[_from][_tokenCollateralAddress] -= _amountCollateral;
        emit CollateralRedeemed(_from, _to, _tokenCollateralAddress, _amountCollateral);

        bool success = IERC20(_tokenCollateralAddress).transfer(_to, _amountCollateral);

        if (!success) {
            revert DSCEngine__TransferFailed();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
    * Return how close to liquidation a user is
    * If a user goes bellow 1, then they can get liquidated
    */
    function _healthFactor(address _user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformationOfTheUser(_user);
				
				if (totalDscMinted == 0) {
					revert DSCEngine__MustHaveMintedDsc();
				}
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUDITION_THRESHOLD) / LIQUDITION_PRECISION;

        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address _user) internal view {
        uint256 userHeltFactor = _healthFactor(_user);

        if (userHeltFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHeltFactor(userHeltFactor);
        }
    }

    function getAccountCollateralValue(address _user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[_user][token];
            totalCollateralValueInUsd += getTokenUsdValue(token, amount);
        }

        return totalCollateralValueInUsd;
    }

    function getTokenUsdValue(address _token, uint256 _amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        return ((uint256(price) * ADDITIONAL_FEE_PRECISION) * _amount) / PRECISION;
    }

    function getTokenAmountFromUsd(address _token, uint256 _usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        return (_usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEE_PRECISION);
    }

		function getAccountInformation(address _user) public view returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {
			(totalDscMinted, collateralValueInUsd) = _getAccountInformationOfTheUser(_user);
		}

    function getHealthFactor(address _user) public view returns (uint256) {
			return _healthFactor(_user);
    }
}
