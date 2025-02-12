// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

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

contract DSCEngine {
	
}
