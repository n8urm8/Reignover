// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

interface IBuilder {
    function getBuildingCount() external view returns(uint);
    function addResource(address _resourceAddress) external;

}