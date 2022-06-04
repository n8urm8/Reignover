// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

interface IResourceManager {
    function setBuildingLevel(uint _cityId, uint _buildingId) external;
    function claimCityResources(uint _cityId) external;
    function claimCityResourcesAll(address _player) external;
}