// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { DecentralizedStableCoin } from "./DecentralizedStableCoin.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

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

    uint256 private constant ADDITIONAL_FEE_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e16;
    uint256 private constant LIQUDITION_THRESHOLD = 50;
    uint256 private constant LIQUDITION_PRECISION = 100;
    uint8 private constant MIN_HELT_FACTOR = 1;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinter) private s_amountDscMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);

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

        if (!success) {
            revert DSCEngine__TransferFaild();
        }
    }

    function redeemCollateralForDsc() external {
        // Redeem DSC
        // Withdraw collateral
    }

    function redeemCollateral() external {}

    function mintDsc(uint256 _amountDscToMint) external moreThanZero(_amountDscToMint) nonReentrant {
        s_amountDscMinted[msg.sender] += _amountDscToMint;
        _revertIfHeltFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, _amountDscToMint);

        if (!minted) {
            revert DSCEngine__MintFailed();
        }
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

    function _getAccountInformationOfTheUser(address _user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_amountDscMinted[_user];
        collateralValueInUsd = getAccountCollateralValue(_user);
    }

    /*
    * Return how close to liquidation a user is
    * If a user goes bellow 1, then they can get liquidated
    */
    function _heltFactor(address _user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformationOfTheUser(_user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUDITION_THRESHOLD) / LIQUDITION_PRECISION;

        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHeltFactorIsBroken(address _user) internal view {
        uint256 userHeltFactor = _heltFactor(_user);

        if (userHeltFactor < MIN_HELT_FACTOR) {
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

        return ((uint256(price) * ADDITIONAL_FEE_PRECISION) * 10) / PRECISION;
    }
}
