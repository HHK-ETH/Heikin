// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "./interfaces/IAggregatorInterface.sol";
import {ITrident, IPool, IBentoBox} from "./interfaces/ITrident.sol";

struct DcaData {
    address owner;
    address sellToken;
    address buyToken;
    IAggregatorInterface sellTokenPriceFeed;
    IAggregatorInterface buyTokenPriceFeed;
    uint64 epochDuration;
    uint8 decimalsDiff;
    uint256 buyAmount;
    uint256 lastBuy;
    uint256 balance;
}

contract Heikin {
    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------
    error OwnerOnly();
    error ToClose();
    error InvalidDca();
    error InsufficientBalance();

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------
    event CreateDCA(uint256 dcaId);
    event ExecuteDCA(uint256 dcaId, uint256 received);
    event WithdrawFromDca(uint256 dcaId, uint256 share);
    event DeleteDca(uint256 dcaId);

    /// -----------------------------------------------------------------------
    /// Immutable variables
    /// -----------------------------------------------------------------------

    ///@notice address of the BentoBox
    IBentoBox immutable bentobox;

    /// -----------------------------------------------------------------------
    /// Mutable variables
    /// -----------------------------------------------------------------------

    ///@notice Store dcaData
    mapping(uint256 => DcaData) internal dcaData;

    ///@notice Store dca count
    uint256 internal dcaCounter;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(address _bentobox) {
        bentobox = IBentoBox(_bentobox);
    }

    /// -----------------------------------------------------------------------
    /// State change functions
    /// -----------------------------------------------------------------------

    ///@notice Create a new Dca
    ///@param owner Address of the owner of the vault
    ///@param sellToken Address of the token to sell
    ///@param buyToken Address of the token to buy
    ///@param sellTokenPriceFeed Address of the priceFeed to use to determine sell token price
    ///@param buyTokenPriceFeed Address of the priceFeed to use to determine buy token price
    ///@param epochDuration Minimum time between each buy
    ///@param decimalsDiff buyToken decimals - sellToken decimals
    ///@param amount Amount to use on each buy
    function createDCA(
        address owner,
        address sellToken,
        address buyToken,
        address sellTokenPriceFeed,
        address buyTokenPriceFeed,
        uint64 epochDuration,
        uint8 decimalsDiff,
        uint256 amount
    ) external returns (uint256 newDcaId) {
        newDcaId = dcaCounter;
        dcaData[dcaCounter] = DcaData(
            owner,
            sellToken,
            buyToken,
            IAggregatorInterface(buyTokenPriceFeed),
            IAggregatorInterface(sellTokenPriceFeed),
            epochDuration,
            decimalsDiff,
            amount,
            0,
            0
        );
        dcaCounter += 1;
        emit CreateDCA(dcaCounter);
    }

    ///@notice Execute the DCA buy
    ///@param dcaId dca id
    ///@param path Trident path
    function executeDCA(uint256 dcaId, ITrident.Path[] calldata path) external {
        DcaData memory data = dcaData[dcaId];

        if (data.lastBuy + data.epochDuration > block.timestamp) {
            revert ToClose();
        }
        data.lastBuy = block.timestamp;

        //query oracles and determine minAmount, both priceFeed must have same decimals.
        uint256 sellTokenPrice = uint256(
            data.sellTokenPriceFeed.latestAnswer()
        );
        uint256 buyTokenPrice = uint256(data.buyTokenPriceFeed.latestAnswer());

        uint256 minAmount;
        unchecked {
            uint256 ratio = (sellTokenPrice * 1e24) / buyTokenPrice;
            minAmount =
                (((ratio * data.buyAmount) * (10**data.decimalsDiff)) * 99) /
                100 /
                1e24;
        }

        //convert amount to bento shares
        uint256 buyAmount = bentobox.toShare(
            data.sellToken,
            data.buyAmount,
            false
        );
        data.balance -= buyAmount;

        //execute the swap on trident by default but since we don't check if pools are whitelisted
        //an intermediate contract could redirect the swap to pools outside of trident.
        bentobox.transfer(
            data.sellToken,
            address(this),
            path[0].pool,
            buyAmount
        );
        uint256 amountOut;
        for (uint256 i; i < path.length; ) {
            amountOut = IPool(path[i].pool).swap(path[i].data);
            unchecked {
                ++i;
            }
        }

        //transfer minAmount to the owner.
        bentobox.transfer(
            data.buyToken,
            address(this),
            data.owner,
            bentobox.toShare(data.buyToken, minAmount, false)
        );
        //transfer remaining shares from the DCA to the executor as a reward.
        bentobox.transfer(
            data.buyToken,
            address(this),
            msg.sender,
            amountOut - bentobox.toShare(data.buyToken, minAmount, false)
        );

        emit ExecuteDCA(data.lastBuy, minAmount);
    }

    ///@notice Allow the owner to withdraw its token from the DCA
    function depositIntoDca(
        uint256 dcaId,
        uint256 shares,
        bool fromBento
    ) external {
        DcaData memory data = dcaData[dcaId];
        if (data.sellToken != address(0)) {
            revert InvalidDca();
        }
        if (fromBento) {
            bentobox.transfer(
                data.sellToken,
                msg.sender,
                address(this),
                shares
            );
        } else {
            bentobox.deposit(
                data.sellToken,
                msg.sender,
                address(this),
                0,
                shares
            );
        }
        emit WithdrawFromDca(dcaId, shares);
    }

    ///@notice Allow the owner to withdraw its token from the DCA
    function withdrawFromDca(uint256 dcaId, uint256 shares) external {
        DcaData memory data = dcaData[dcaId];
        if (msg.sender != data.owner) {
            revert OwnerOnly();
        }
        if (shares > data.balance) {
            revert InsufficientBalance();
        }
        bentobox.transfer(data.sellToken, address(this), data.owner, shares);
        emit WithdrawFromDca(dcaId, shares);
    }

    ///@notice Allow the owner to delete the DCA
    function deleteDca(uint256 dcaId) external {
        DcaData memory data = dcaData[dcaId];
        if (msg.sender != data.owner) {
            revert OwnerOnly();
        }
        bentobox.transfer(
            data.sellToken,
            address(this),
            data.owner,
            data.balance
        );
        delete dcaData[dcaId];
        emit DeleteDca(dcaId);
    }

    /// -----------------------------------------------------------------------
    /// No state change functions
    /// -----------------------------------------------------------------------

    function getDcaData(uint256 dcaId) external view returns (DcaData memory) {
        return dcaData[dcaId];
    }
}
