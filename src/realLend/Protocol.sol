// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {DutchAuction} from "./DutchAuction.sol";

import {console2} from "forge-std/console2.sol";

/// @title Protocol
contract Protocol is ERC721 {
    struct Loan {
        uint256 loanId;
        address oracle; // address of the oracle that declared the price of the collateral
        address borrower; // address of the borrower
        ERC20 borrowAsset; // asset the borrower is borrowing
        address lender; // address of the lender
        ERC721 collateralAsset; // asset the borrower is borrowing
        uint256 collateralAssetId; // id of the collateral asset
        uint256 collateralPercentage; // 100% would mean the oracle deposits 100% of the collateral value
        uint256 borrowAmount; // amount of borrowAsset the borrower is borrowing
        uint256 interestRate; // interest rate for the loan divided by INTEREST_PRECISION(ie 200% over course of loan is ok)
        uint256 startTimestamp; // block.timestamp for when the loan starts
        uint256 expiration; // block.timestamp for when the loan expires and
        bool borrowerHasRepaid; // whether the borrower has repaid the loan
        bool isActive; // whether the loan is still active
    }

    struct DutchAuction {
        uint256 loanId;
        address seller;
        uint256 startingPrice;
        uint256 startAt;
        uint256 expiresAt;
        uint256 discountRate;
        address protocol;
        ERC20 borrowAsset;
        bool isActive;
    }

    mapping(uint256 => Loan) public loans;
    mapping(uint256 => DutchAuction) public dutchAuctions;
    uint256 public numLoans;
    uint256 public constant INTEREST_PRECISION = 10_000; // 100%

    /// @dev Borrower declares they want to take a loan on their vacation cottage
    function borrowerCreateLoan(
        ERC20 borrowAsset,
        ERC721 collateralAsset,
        uint256 collateralAssetId,
        uint256 borrowAmount,
        uint256 interestRate,
        uint256 expiration
    ) external returns (Loan memory) {
        collateralAsset.transferFrom(
            msg.sender,
            address(this),
            collateralAssetId
        );
        Loan memory loan = Loan({
            loanId: numLoans,
            oracle: address(0),
            borrower: msg.sender,
            borrowAsset: borrowAsset,
            lender: address(0),
            collateralAsset: collateralAsset,
            collateralAssetId: collateralAssetId,
            collateralPercentage: 0,
            borrowAmount: borrowAmount,
            interestRate: interestRate,
            startTimestamp: 0,
            expiration: expiration,
            borrowerHasRepaid: false,
            isActive: false
        });
        loans[numLoans++] = loan;
        _mint(msg.sender, numLoans - 1);
    }

    /// @dev An oracle declares their vacation cottage is worth 200k USDC. They put up 200k as
    ///a part of the loan as a bond.
    function oraclePriceCollateral(
        uint256 loanId,
        uint256 collateralPercentage
    ) external returns (uint256) {
        Loan memory loan = loans[loanId];
        require(loanId < numLoans, "Loan does not exist");
        require(!loan.isActive, "Loan is already active");
        require(
            loan.collateralPercentage == 0,
            "Collateral percentage already set"
        );
        loans[loanId].oracle = msg.sender;
        loans[loanId].collateralPercentage = collateralPercentage;
        loan.borrowAsset.transferFrom(
            msg.sender,
            address(this),
            calculateCollateralAmount(loanId)
        );
    }

    /// @dev The lender gives the borrower 100k USDC at 10% interest for 10 years.
    function lenderFillLoan(uint256 loanId) external {
        Loan memory loan = loans[loanId];
        require(loanId < numLoans, "Loan does not exist");
        require(!loan.isActive, "Loan is already active");
        require(loan.oracle != address(0), "Oracle not set");
        require(loan.lender == address(0), "Lender already set");
        require(
            loan.borrowAsset.transferFrom(
                msg.sender,
                address(this),
                loan.borrowAmount
            ),
            "Transfer failed"
        );
        loans[loanId].lender = msg.sender;
        loans[loanId].isActive = true;
        loans[loanId].startTimestamp = block.timestamp;
    }

    /// @dev The borrower borrows the 100k USDC
    function borrowerWithdrawLoan(uint256 loanId) external {
        Loan memory loan = loans[loanId];
        require(loanId < numLoans, "Loan does not exist");
        require(loan.borrower == msg.sender, "Not the borrower");
        require(loan.isActive, "Loan is not active");
        loans[loanId].borrowAsset.transfer(
            msg.sender,
            loans[loanId].borrowAmount
        );
    }

    /// @dev If the lender wants to stop lending, they can trigger a dutch auction and sell their
    /// loan position to someone else. A dutch auction would start at 1m USDC and decrease, and
    /// the winner of the dutch auction receives the loan position.
    function lenderEndLoan(uint256 loanId) external {
        Loan memory loan = loans[loanId];
        require(loanId < numLoans, "Loan does not exist");
        require(loan.lender == msg.sender, "Not the lender");
        _burn(loanId);
        DutchAuction memory dutchAuction = DutchAuction({
            loanId: loanId,
            seller: msg.sender,
            startingPrice: calculatePrincipalWithInterestAmount(loanId),
            startAt: block.timestamp,
            expiresAt: block.timestamp + 7 days,
            discountRate: calculatePrincipalWithInterestAmount(loanId) / 7 days,
            protocol: address(this),
            borrowAsset: loan.borrowAsset,
            isActive: true
        });
        dutchAuctions[loanId] = dutchAuction;
    }

    /// @dev If the loan reaches maturity, we check if the interest + principal has been paid back
    /// to the loan. If not, the lender sells the vacation cottage to the oracle.
    function lenderClaimFinishedLoan(uint256 loanId) external {
        Loan memory loan = loans[loanId];
        require(loanId < numLoans, "Loan does not exist");
        require(loan.lender == msg.sender, "Not the lender");
        require(loan.isActive, "Loan is not active");
        if (loan.borrowerHasRepaid) {
            loan.borrowAsset.transfer(
                loan.lender,
                calculatePrincipalWithInterestAmount(loanId)
            );
        } else {
            loan.borrowAsset.transfer(
                loan.lender,
                calculateCollateralAmount(loanId)
            );
            loan.collateralAsset.transferFrom(
                address(this),
                loan.lender,
                loan.collateralAssetId
            );
        }
        _burn(loanId);
    }

    /// @dev If the borrower wants to end the loan, they pay back the loan with interest and
    /// receive back their cottage.
    function borrowerEndLoan(uint256 loanId) external {
        Loan memory loan = loans[loanId];
        require(loanId < numLoans, "Loan does not exist");
        require(loan.borrower == msg.sender, "Not the borrower");
        require(loan.isActive, "Loan is not active");
        loans[loanId].isActive = false;
        require(
            loan.borrowAsset.transferFrom(
                msg.sender,
                loan.lender,
                calculatePrincipalWithInterestAmount(loanId)
            ),
            "Failed to transfer principal + interest"
        );
        loan.collateralAsset.transferFrom(
            address(this),
            loan.borrower,
            loan.collateralAssetId
        );
    }

    /// @dev If the loan reaches maturity, we check if the interest + principal has been paid back
    /// to the loan. If not, the lender sells the vacation cottage to the oracle.
    function borrowerClaimFinishedLoan(uint256 loanId) external {
        Loan memory loan = loans[loanId];
        require(loanId < numLoans, "Loan does not exist");
        require(loan.borrower == msg.sender, "Not the borrower");
        require(loan.isActive, "Loan is not active");
        if (loan.borrowerHasRepaid) {
            loan.borrowAsset.transfer(
                msg.sender,
                calculatePrincipalWithInterestAmount(loanId)
            );
        } else {
            loan.borrowAsset.transfer(
                msg.sender,
                calculateCollateralAmount(loanId)
            );
            loan.collateralAsset.transferFrom(
                address(this),
                msg.sender,
                loan.collateralAssetId
            );
        }
    }

    /// @dev The borrower repays the loan with interest and receives back their cottage.
    function borrowerRepayLoan(uint256 loanId) external {
        Loan memory loan = loans[loanId];
        require(loanId < numLoans, "Loan does not exist");
        require(loan.borrower == msg.sender, "Not the borrower");
        require(loan.isActive, "Loan is not active");
        loan.borrowAsset.transferFrom(
            msg.sender,
            address(this),
            calculatePrincipalWithInterestAmount(loanId)
        );
        loan.collateralAsset.transferFrom(
            address(this),
            msg.sender,
            loan.collateralAssetId
        );
        loans[loanId].borrowerHasRepaid = true;
    }

    constructor() ERC721("Loan", "LN") {}

    function tokenURI(uint256 id) public pure override returns (string memory) {
        return "";
    }

    function calculateCollateralAmount(
        uint256 loanId
    ) public view returns (uint256) {
        require(loanId < numLoans, "Loan does not exist");
        Loan memory loan = loans[loanId];
        return
            (loan.borrowAmount * loan.collateralPercentage) /
            INTEREST_PRECISION;
    }

    function calculatePrincipalWithInterestAmount(
        uint256 loanId
    ) public view returns (uint256) {
        require(loanId < numLoans, "Loan does not exist");
        Loan memory loan = loans[loanId];

        if (block.timestamp >= loan.expiration) {
            // If the loan has expired, return the full amount with interest
            return
                (loan.borrowAmount * loan.interestRate) /
                INTEREST_PRECISION +
                loan.borrowAmount;
        } else {
            // If the loan hasn't expired, calculate pro-rata interest
            uint256 elapsedTime = block.timestamp - loan.startTimestamp;
            uint256 totalDuration = loan.expiration - loan.startTimestamp;
            uint256 proRataInterest = (loan.borrowAmount *
                loan.interestRate *
                elapsedTime) / (INTEREST_PRECISION * totalDuration);
            return loan.borrowAmount + proRataInterest;
        }
    }

    function getPrice(uint256 loanId) public view returns (uint256) {
        DutchAuction memory dutchAuction = dutchAuctions[loanId];
        uint256 timeElapsed = block.timestamp - dutchAuction.startAt;
        uint256 discount = dutchAuction.discountRate * timeElapsed;
        return dutchAuction.startingPrice - discount;
    }

    function buy(uint256 loanId) public {
        DutchAuction memory dutchAuction = dutchAuctions[loanId];
        require(block.timestamp < dutchAuction.expiresAt, "auction expired");

        uint256 price = getPrice(loanId);
        dutchAuction.borrowAsset.transferFrom(
            msg.sender,
            dutchAuction.seller,
            price
        );
        dutchAuction.isActive = false;
        _mint(msg.sender, loanId);
    }

    function loan(uint256 loanId) external view returns (Loan memory) {
        return loans[loanId];
    }

    function allLoans() external view returns (Loan[] memory) {
        Loan[] memory allLoans = new Loan[](numLoans);
        for (uint256 i = 0; i < numLoans; i++) {
            allLoans[i] = loans[i];
        }
        return allLoans;
    }

    function myBorrows(address user) external view returns (Loan[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < numLoans; i++) {
            if (loans[i].borrower == user) {
                count++;
            }
        }

        Loan[] memory userBorrows = new Loan[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < numLoans; i++) {
            if (loans[i].borrower == user) {
                userBorrows[index] = loans[i];
                index++;
            }
        }

        return userBorrows;
    }

    function myPrices(address user) external view returns (Loan[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < numLoans; i++) {
            if (loans[i].oracle == user) {
                count++;
            }
        }

        Loan[] memory userPrices = new Loan[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < numLoans; i++) {
            if (loans[i].oracle == user) {
                userPrices[index] = loans[i];
                index++;
            }
        }

        return userPrices;
    }

    function myLends(address user) external view returns (Loan[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < numLoans; i++) {
            if (loans[i].lender == user) {
                count++;
            }
        }

        Loan[] memory userLends = new Loan[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < numLoans; i++) {
            if (loans[i].lender == user) {
                userLends[index] = loans[i];
                index++;
            }
        }

        return userLends;
    }

    function activeDutchAuctions()
        external
        view
        returns (DutchAuction[] memory)
    {
        uint256 count = 0;
        for (uint256 i = 0; i < numLoans; i++) {
            if (dutchAuctions[i].isActive) {
                count++;
            }
        }

        DutchAuction[] memory activeAuctions = new DutchAuction[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < numLoans; i++) {
            if (dutchAuctions[i].isActive) {
                activeAuctions[index] = dutchAuctions[i];
                index++;
            }
        }

        return activeAuctions;
    }
}
