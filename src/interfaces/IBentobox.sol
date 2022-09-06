// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IBentoBox {
    function transfer(
        address token,
        address from,
        address to,
        uint256 share
    ) external;

    function balanceOf(address token, address account)
        external
        returns (uint256);

    function toAmount(
        address token,
        uint256 share,
        bool roundUp
    ) external returns (uint256);

    function toShare(
        address token,
        uint256 amount,
        bool roundUp
    ) external returns (uint256);
}
