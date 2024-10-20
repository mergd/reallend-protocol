// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {Protocol} from "src/realLend/Protocol.sol";
import {USDC} from "src/USDC.sol";
import {Cottage} from "src/realLend/Cottage.sol";
import {DutchAuction} from "src/realLend/DutchAuction.sol";
contract ProtocolTest is Test {
    using stdStorage for StdStorage;

    Protocol protocol;
    USDC borrowAsset;
    Cottage collateralAsset;

    address borrower = address(0x1);
    address lender = address(0x2);
    address oracle = address(0x3);

    uint256 interestRate = 1000; // 10%
    uint256 collateralPercentage = 1000; // 10%
    uint256 collateralId = 1;
    uint256 borrowAmount = 100;

    function setUp() external {
        protocol = new Protocol();
        borrowAsset = new USDC();
        collateralAsset = new Cottage();
        borrowAsset.mint(lender, 100);
        borrowAsset.mint(oracle, 10);
        collateralAsset.mint(borrower, 1);
    }

    function setUpLoan() internal returns (uint256 loanId, uint256 expiration) {
        expiration = block.timestamp + 100;

        vm.startPrank(borrower);
        collateralAsset.approve(address(protocol), collateralId);
        protocol.borrowerCreateLoan(
            borrowAsset,
            collateralAsset,
            collateralId,
            borrowAmount,
            interestRate,
            expiration
        );
        vm.stopPrank();

        loanId = protocol.numLoans() - 1;

        vm.startPrank(oracle);
        borrowAsset.approve(
            address(protocol),
            (protocol.loan(loanId).borrowAmount * collateralPercentage) /
                protocol.INTEREST_PRECISION()
        );
        protocol.oraclePriceCollateral(loanId, collateralPercentage);
        vm.stopPrank();

        vm.startPrank(lender);
        borrowAsset.approve(
            address(protocol),
            protocol.loan(loanId).borrowAmount
        );
        protocol.lenderFillLoan(loanId);
        vm.stopPrank();

        vm.startPrank(borrower);
        protocol.borrowerWithdrawLoan(loanId);
        vm.stopPrank();
    }

    function test_borrowerEndLoan() external {
        (uint256 loanId, uint256 expiration) = setUpLoan();

        vm.startPrank(borrower);
        vm.warp(expiration);
        uint256 principalWithInterestAmount = protocol
            .calculatePrincipalWithInterestAmount(loanId);
        borrowAsset.mint(
            borrower,
            principalWithInterestAmount - borrowAsset.balanceOf(borrower)
        );
        borrowAsset.approve(address(protocol), principalWithInterestAmount);
        protocol.borrowerEndLoan(loanId);
        vm.stopPrank();
    }

    function test_lenderClaimFinishedLoanAndBorrowerRepays() external {
        (uint256 loanId, uint256 expiration) = setUpLoan();

        vm.warp(expiration);
        vm.startPrank(borrower);
        borrowAsset.approve(
            address(protocol),
            protocol.calculatePrincipalWithInterestAmount(loanId)
        );
        borrowAsset.mint(
            borrower,
            protocol.calculatePrincipalWithInterestAmount(loanId) +
                borrowAsset.balanceOf(borrower)
        );
        protocol.borrowerRepayLoan(loanId);
        vm.stopPrank();

        vm.startPrank(lender);
        protocol.lenderClaimFinishedLoan(loanId);
        vm.stopPrank();
    }

    function test_lenderClaimFinishedLoanAndBorrowerDoesNotRepay() external {
        (uint256 loanId, uint256 expiration) = setUpLoan();

        vm.warp(expiration);
        vm.startPrank(lender);
        protocol.lenderClaimFinishedLoan(loanId);
        vm.stopPrank();
    }

    function test_borrowerClaimFinishedLoanAnBorrowerDoesNotRepay() external {
        (uint256 loanId, uint256 expiration) = setUpLoan();

        vm.warp(expiration);
        vm.startPrank(borrower);
        protocol.borrowerClaimFinishedLoan(loanId);
        vm.stopPrank();
    }

    function test_borrowerClaimFinishedLoanAnBorrowerDidRepay() external {
        (uint256 loanId, uint256 expiration) = setUpLoan();

        vm.warp(expiration);
        vm.startPrank(borrower);
        borrowAsset.approve(
            address(protocol),
            protocol.calculatePrincipalWithInterestAmount(loanId)
        );
        borrowAsset.mint(
            borrower,
            protocol.calculatePrincipalWithInterestAmount(loanId) +
                borrowAsset.balanceOf(borrower)
        );
        protocol.borrowerRepayLoan(loanId);
        vm.stopPrank();

        vm.startPrank(borrower);
        protocol.borrowerClaimFinishedLoan(loanId);
        vm.stopPrank();
        protocol.myBorrows(borrower);
        protocol.myPrices(oracle);
        protocol.myLends(lender);
        protocol.activeDutchAuctions();
    }

    function test_DutchAuction() external {
        (uint256 loanId, uint256 expiration) = setUpLoan();

        vm.warp(expiration);
        vm.startPrank(lender);
        protocol.lenderEndLoan(loanId);
        vm.stopPrank();

        vm.startPrank(oracle);
        borrowAsset.mint(oracle, protocol.getPrice(loanId));
        borrowAsset.approve(address(protocol), protocol.getPrice(loanId));
        protocol.buy(loanId);
        vm.stopPrank();
    }
}
