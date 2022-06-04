// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

interface IKingdoms {
    function createCity(string memory _name) external;
    function cityTransfer(uint _id, address _newOwner) external;
    function updateBuilding(uint _cityId, uint _buildingId, uint _newBuildingLevel) external;
    function getCityOwner(uint _cityId) external view returns(address);
    function getCityBuildingsWithLevel(uint _cityId) external view returns(uint[] memory);
    function getOwnerCities(address _owner) external view returns(uint[] memory);
    function addResource(address _resourceAddress) external;
    function getTotalForges(address _player) external view returns(uint);
}