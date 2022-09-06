// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "./interfaces/IAggregatorInterface.sol";
import "./interfaces/ITrident.sol";

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
}

contract Heikin {
    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------
    error OwnerOnly();
    error ToClose();

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------
    event ExecuteDCA(uint256 timestamp, uint256 amount);
    event Withdraw(uint256 share);
    event CreateDCA(uint256 newDcaId);

    /// -----------------------------------------------------------------------
    /// Immutable variables
    /// -----------------------------------------------------------------------

    ///@notice address of the BentoBox
    IBentoBox immutable bentobox;

    /// -----------------------------------------------------------------------
    /// Mutable variables
    /// -----------------------------------------------------------------------

    ///@notice Store dcaData
    mapping(uint256 => DcaData) public dcaData;

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
    ) external {
        dcaData[dcaCounter] = DcaData(
            owner,
            sellToken,
            buyToken,
            IAggregatorInterface(buyTokenPriceFeed),
            IAggregatorInterface(sellTokenPriceFeed),
            epochDuration,
            decimalsDiff,
            amount,
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

        //execute the swap on trident by default but since we don't check if pools are whitelisted
        //an intermediate contract could redirect the swap to pools outside of trident.
        bentobox.transfer(
            data.sellToken,
            address(this),
            path[0].pool,
            buyAmount
        );
        for (uint256 i; i < path.length; ) {
            IPool(path[i].pool).swap(path[i].data);
            unchecked {
                ++i;
            }
        }

        //transfer minAmount minus 1% fee to the owner.
        bentobox.transfer(
            data.buyToken,
            address(this),
            data.owner,
            bentobox.toShare(data.buyToken, minAmount, false)
        );
        //transfer remaining shares (up to 1% of minAmount) from the vault to dca executor as a reward.
        bentobox.transfer(
            data.buyToken,
            address(this),
            msg.sender,
            bentobox.balanceOf(data.buyToken, address(this))
        );

        emit ExecuteDCA(data.lastBuy, minAmount);
    }

    ///@notice Allow the owner to withdraw its token from the vault
    function withdraw(uint256 dcaId, uint256 shares) external {
        DcaData memory data = dcaData[dcaId];
        if (msg.sender != data.owner) {
            revert OwnerOnly();
        }
        bentobox.transfer(data.sellToken, address(this), data.owner, shares);
        emit Withdraw(shares);
    }
}
