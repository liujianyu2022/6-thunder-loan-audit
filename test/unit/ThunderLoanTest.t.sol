// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { BaseTest, ThunderLoan } from "./BaseTest.t.sol";
import { AssetToken } from "../../src/protocol/AssetToken.sol";
import { MockFlashLoanReceiver } from "../mocks/MockFlashLoanReceiver.sol";

contract ThunderLoanTest is BaseTest {
    uint256 constant AMOUNT = 10e18;
    uint256 constant DEPOSIT_AMOUNT = AMOUNT * 100;
    address liquidityProvider = address(123);
    address user = address(456);
    MockFlashLoanReceiver mockFlashLoanReceiver;

    function setUp() public override {
        super.setUp();                              // 调用了父合约 BaseTest 的 setUp()

        // 以user的身份创建一个thunderLoanReceiver
        vm.prank(user);
        mockFlashLoanReceiver = new MockFlashLoanReceiver(address(thunderLoan));    
    }

    // 检查闪电贷的owner
    function testInitializationOwner() public {
        assertEq(thunderLoan.owner(), thunderLoanOwner);
    }

    function testOnlyOwnerCanSetTokens() public {
        vm.prank(liquidityProvider);                    // only the owner of thunder can set allowed token
        vm.expectRevert();
        thunderLoan.setAllowedToken(tokenA, true);
    }

    function testSettingTokenCreatesAsset() public {
        vm.prank(thunderLoan.owner());                  // only the owner of thunder can set allowed token
        AssetToken assetToken = thunderLoan.setAllowedToken(tokenA, true);
        assertEq(thunderLoan.isAllowedToken(tokenA), true);
        assertEq(address(thunderLoan.getAssetFromToken(tokenA)), address(assetToken));
    }

    function testCantDepositUnapprovedTokens() public {
        tokenA.mint(liquidityProvider, AMOUNT);                 // 给 liquidityProvider mint 1e18 个 tokenA
        
        vm.startPrank(liquidityProvider);
        tokenA.approve(address(thunderLoan), AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(
                ThunderLoan.ThunderLoan__NotAllowedToken.selector, 
                address(tokenA)
            )
        );
        
        thunderLoan.deposit(tokenA, AMOUNT);

        vm.stopPrank();
    }

    modifier setAllowedToken() {
        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA, true);
        _;
    }

    function testDepositMintsAssetAndUpdatesBalance() public setAllowedToken {
        tokenA.mint(liquidityProvider, AMOUNT);

        vm.startPrank(liquidityProvider);
        tokenA.approve(address(thunderLoan), AMOUNT);
        thunderLoan.deposit(tokenA, AMOUNT);
        vm.stopPrank();

        /*  liquidityProvider  -- tokenA -->  assetToken
                    ^                               |
                    |                               |
                    +-----<----  assetToken <-------+  
        */
        AssetToken assetToken = thunderLoan.getAssetFromToken(tokenA);
        assertEq(tokenA.balanceOf(address(assetToken)), AMOUNT);
        assertEq(assetToken.balanceOf(liquidityProvider), AMOUNT);
    }

    // liquidityProvider 存入 1000 tokenA 到 thunderLoan
    modifier hasDeposits() {
        vm.startPrank(liquidityProvider);
        tokenA.mint(liquidityProvider, DEPOSIT_AMOUNT);         // 1000e18
        tokenA.approve(address(thunderLoan), DEPOSIT_AMOUNT);
        thunderLoan.deposit(tokenA, DEPOSIT_AMOUNT);
        vm.stopPrank();
        _;
    }

    // thunderLoan 合约中有了 1000 tokenA 
    function testFlashLoan() public setAllowedToken hasDeposits {
        uint256 amountToBorrow = AMOUNT * 10;                                               // 借出 100 tokenA
        uint256 calculatedFee = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);       // 

        vm.startPrank(user);

        // Mint "AMOUNT" of tokenA to the MockFlashLoanReceiver to ensure it has sufficient balance to cover the fee
        tokenA.mint(address(mockFlashLoanReceiver), AMOUNT); 
        assertEq(tokenA.balanceOf(address(mockFlashLoanReceiver)), AMOUNT);

        // flash loan
        thunderLoan.flashloan(address(mockFlashLoanReceiver), tokenA, amountToBorrow, "");

        vm.stopPrank();
        
        assertEq(calculatedFee, (amountToBorrow * 3 * 1e15) / 1e18);                    // fee ratio: 0.3%
        assertEq(mockFlashLoanReceiver.getBalanceDuring(), amountToBorrow + AMOUNT);
        assertEq(mockFlashLoanReceiver.getBalanceAfter(), AMOUNT - calculatedFee);
    }

    // liquidityProvider 存入了 1000 tokenA，因此 thunderLoan 合约中有了 1000 tokenA，liquidityProvider 拥有了 1000 assetToken 
    function testRedeem() public setAllowedToken hasDeposits {
        uint256 amountToBorrow = AMOUNT * 10;                                               // 借出 100 tokenA
        uint256 calculatedFee = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);       // fee = 100 * 0.3% = 0.3

        vm.startPrank(user);
        tokenA.mint(address(mockFlashLoanReceiver), AMOUNT);                                // 给 user 10 tokenA，以便于偿还 fee
        thunderLoan.flashloan(address(mockFlashLoanReceiver), tokenA, amountToBorrow, "");
        vm.stopPrank();

        AssetToken assetToken = thunderLoan.getAssetFromToken(tokenA);

        assertEq(calculatedFee, 100 * 3e15);                                                      
        assertEq(tokenA.balanceOf(address(assetToken)), DEPOSIT_AMOUNT + calculatedFee);    // ( 1000 + 0.3 ) tokenA

        vm.startPrank(liquidityProvider);
        thunderLoan.redeem(tokenA, type(uint256).max);                                      // liquidityProvider 取出全部 tokenA
        vm.stopPrank();

        assertEq(tokenA.balanceOf(address(assetToken)), 0);                                         // assetToken 合约上剩余 0 tokenA
        assertEq(tokenA.balanceOf(address(liquidityProvider)), DEPOSIT_AMOUNT + calculatedFee);     // liquidityProvider 此时有 (1000 + 0.3) tokenA
    }
}
