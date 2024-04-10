// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IComet {
    function supply(address asset, uint amount) external virtual;
    function supplyTo(address dst, address asset, uint amount) external virtual;
    function supplyFrom(
        address from,
        address dst,
        address asset,
        uint amount
    ) external virtual;

    function transfer(address dst, uint amount) external virtual returns (bool);
    function transferFrom(
        address src,
        address dst,
        uint amount
    ) external virtual returns (bool);

    function transferAsset(
        address dst,
        address asset,
        uint amount
    ) external virtual;
    function transferAssetFrom(
        address src,
        address dst,
        address asset,
        uint amount
    ) external virtual;

    function withdraw(address asset, uint amount) external virtual;
    function withdrawTo(
        address to,
        address asset,
        uint amount
    ) external virtual;
    function withdrawFrom(
        address src,
        address to,
        address asset,
        uint amount
    ) external virtual;

    function approveThis(
        address manager,
        address asset,
        uint amount
    ) external virtual;
    function withdrawReserves(address to, uint amount) external virtual;

    function absorb(
        address absorber,
        address[] calldata accounts
    ) external virtual;
    function buyCollateral(
        address asset,
        uint minAmount,
        uint baseAmount,
        address recipient
    ) external virtual;
    function quoteCollateral(
        address asset,
        uint baseAmount
    ) external view virtual returns (uint);

    function getCollateralReserves(
        address asset
    ) external view virtual returns (uint);
    function getReserves() external view virtual returns (int);
    function getPrice(address priceFeed) external view virtual returns (uint);

    function isBorrowCollateralized(
        address account
    ) external view virtual returns (bool);
    function isLiquidatable(
        address account
    ) external view virtual returns (bool);

    function totalSupply() external view virtual returns (uint256);
    function totalBorrow() external view virtual returns (uint256);
    function balanceOf(address owner) external view virtual returns (uint256);
    function borrowBalanceOf(
        address account
    ) external view virtual returns (uint256);

    function pause(
        bool supplyPaused,
        bool transferPaused,
        bool withdrawPaused,
        bool absorbPaused,
        bool buyPaused
    ) external virtual;
    function isSupplyPaused() external view virtual returns (bool);
    function isTransferPaused() external view virtual returns (bool);
    function isWithdrawPaused() external view virtual returns (bool);
    function isAbsorbPaused() external view virtual returns (bool);
    function isBuyPaused() external view virtual returns (bool);

    function accrueAccount(address account) external virtual;
    function getSupplyRate(
        uint utilization
    ) external view virtual returns (uint64);
    function getBorrowRate(
        uint utilization
    ) external view virtual returns (uint64);
    function getUtilization() external view virtual returns (uint);

    function governor() external view virtual returns (address);
    function pauseGuardian() external view virtual returns (address);
    function baseToken() external view virtual returns (address);
    function baseTokenPriceFeed() external view virtual returns (address);
    function extensionDelegate() external view virtual returns (address);

    /// @dev uint64
    function supplyKink() external view virtual returns (uint);
    /// @dev uint64
    function supplyPerSecondInterestRateSlopeLow()
        external
        view
        virtual
        returns (uint);
    /// @dev uint64
    function supplyPerSecondInterestRateSlopeHigh()
        external
        view
        virtual
        returns (uint);
    /// @dev uint64
    function supplyPerSecondInterestRateBase()
        external
        view
        virtual
        returns (uint);
    /// @dev uint64
    function borrowKink() external view virtual returns (uint);
    /// @dev uint64
    function borrowPerSecondInterestRateSlopeLow()
        external
        view
        virtual
        returns (uint);
    /// @dev uint64
    function borrowPerSecondInterestRateSlopeHigh()
        external
        view
        virtual
        returns (uint);
    /// @dev uint64
    function borrowPerSecondInterestRateBase()
        external
        view
        virtual
        returns (uint);
    /// @dev uint64
    function storeFrontPriceFactor() external view virtual returns (uint);

    /// @dev uint64
    function baseScale() external view virtual returns (uint);
    /// @dev uint64
    function trackingIndexScale() external view virtual returns (uint);

    /// @dev uint64
    function baseTrackingSupplySpeed() external view virtual returns (uint);
    /// @dev uint64
    function baseTrackingBorrowSpeed() external view virtual returns (uint);
    /// @dev uint104
    function baseMinForRewards() external view virtual returns (uint);
    /// @dev uint104
    function baseBorrowMin() external view virtual returns (uint);
    /// @dev uint104
    function targetReserves() external view virtual returns (uint);

    function numAssets() external view virtual returns (uint8);
    function decimals() external view virtual returns (uint8);

    function initializeStorage() external virtual;
}
