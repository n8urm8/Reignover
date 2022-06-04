// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./libs/Editor.sol";
import "./interfaces/IKingdoms.sol";
import "./interfaces/IResourceToken.sol";
import "./interfaces/IResourceManager.sol";

// Setup: set ResourceManager as editor of this contract, this contract also needs to be an editor of ResourceManager
// set Kingdoms, ResourceManager contract

contract Builder is Editor {

    IKingdoms public Kingdoms; // Kingdoms Contract    
    IResourceManager public ResourceManager; // ResourceManager contract
    address[] public resources; // list of resource tokens
    uint buildingCount; // count of active buildings
    mapping(uint => string) public buildingIdToName; // may need to determine the best way to handle the buildings list
    mapping(uint => mapping(uint => uint)) buildingLevelRequirements; // maps buildings with required buildings + level
    mapping(uint => mapping(uint => uint)) buildingResourceRequirements; // base resources required to build
    mapping(uint => uint) buildingMaxLevel;
    // wallet > cityId > buildingId > time until ready
    mapping(address => mapping(uint => mapping(uint => uint))) public buildingQueue; 

    event NewBuildingLevelRequirements(uint indexed buildingId, uint[] levelRequirements);
    event NewBuildingResourceRequirements(uint indexed buildingId, uint[] resourceRequirements);
    event NewBuildingMaxLevel(uint indexed buildingId, uint maxLevel);
    event BuildingCreated(uint buildingId, string buildingName);
    event NewBuildingName(uint indexed buildingId, string newBuildingName);
    event NewKingdomsContract(address newContract);

    /** 
        @notice creates a new building for cities
        @param _name is the name of the new building
        @param _levelRequirements is array of building's required building levels, length should include building we are adding
        @param _resourceRequirements is array of building required resources, length should include building we are adding, 18 decimals
        @param _maxLevel is max level building can be built
        @dev params can be edited later on if needed
    */ 
    function addBuilding(string memory _name, uint[] memory _levelRequirements, uint[] memory _resourceRequirements, uint _maxLevel ) external onlyOwner {
        buildingIdToName[buildingCount] = _name;
        emit BuildingCreated(buildingCount, _name);
        buildingCount++;
        uint _buildingId = buildingCount-1;
        _setbuildingLevelRequirements(_buildingId, _levelRequirements);
        _setbuildingResourceRequirements(_buildingId, _resourceRequirements);
        _setBuildingMaxLevel(_buildingId, _maxLevel);
    }

    /** @notice returns array of buildings */
    function getBuildings() external view returns(string[] memory) {
        string[] memory buildingList = new string[](buildingCount);
        for (uint i = 0; i < buildingCount; i++) {
            buildingList[i] = buildingIdToName[i];
        }
        return buildingList;
    }

    function getBuildingCount() external view returns(uint) {
        return buildingCount;
    }
    
    /** @notice owner can modify the level requirements of other buildings to be able to build a building
        @dev can only use for buildings that already exist
    */
    function setbuildingLevelRequirements(uint _buildingId, uint[] memory _requirements) public onlyOwner {
        require(_buildingId < buildingCount, "building not active");
        _setbuildingLevelRequirements( _buildingId, _requirements);
    }
    
    /** @notice internal function to set building level requirements during creation
        @param _buildingId building to update
        @param _requirements array index is the buildingID, index value is level required 
    */
    function _setbuildingLevelRequirements(uint _buildingId, uint[] memory _requirements) internal {
        require(_requirements.length == buildingCount, "array length mismatch"); 
        require(_requirements[_buildingId] == 0, "cannot require self");
        for (uint i=0; i < buildingCount; i++) {
            buildingLevelRequirements[_buildingId][i] = _requirements[i];
        }
        emit NewBuildingLevelRequirements(_buildingId, _requirements);
    }

    /** @notice owner can modify the resource requirements of buildings
        @param _requirements remember 18 decimals for token amount
        @dev can only use for buildings that already exist
    */
    function setbuildingResourceRequirements(uint _buildingId, uint[] memory _requirements) public onlyOwner {
        require(_buildingId < buildingCount, "building not active");
        _setbuildingResourceRequirements( _buildingId, _requirements);
    }

    /** @notice internal function to set building resource requirements during creation
        @param _buildingId building to update
        @param _requirements array index is the resource, index value is amount required 
    */
    function _setbuildingResourceRequirements(uint _buildingId, uint[] memory _requirements) internal {
        require(_requirements.length == resources.length, "array length mismatch");
        require(_requirements[0] == 0, "cannot require base token");
        for (uint i=0; i < resources.length; i++) {
            buildingResourceRequirements[_buildingId][i] = _requirements[i];
        }
        emit NewBuildingResourceRequirements(_buildingId, _requirements);
    }

    function setBuildingMaxLevel(uint _buildingId, uint _maxLevel) external onlyOwner {
        _setBuildingMaxLevel(_buildingId, _maxLevel);
    }

    /** @notice sets max level for a building */
    function _setBuildingMaxLevel(uint _buildingId, uint _maxLevel) internal {
        buildingMaxLevel[_buildingId] = _maxLevel;
        emit NewBuildingMaxLevel(_buildingId, _maxLevel);
    }

    function setBuildingName(uint _buildingId, string memory _newName) external onlyOwner {
        buildingIdToName[_buildingId] = _newName;
        emit NewBuildingName(_buildingId, _newName);
    }

    /** @notice used by resource manager when creating a new resource token
        @dev preservation of order of resources is critically important  
    */
    function addResource(address _resourceAddress) external onlyEditor {
        resources.push(_resourceAddress);
    }

    /** @notice only to be used if a token needs to be replaced */
    function editResource(uint _id, address _newAddress) external onlyOwner {
        resources[_id] = _newAddress;
    }

    function getResourceCount() external view returns(uint) {
        return resources.length;
    }

    /** @notice starts building the next level of a building if all requirements met
        @dev pulls building data from Kingdoms contract
    */
    function prepLevelUpBuilding(uint _cityId, uint _buildingId) external {
        require(Kingdoms.getCityOwner(_cityId) == msg.sender, "Not owner of city");
        require(buildingQueue[msg.sender][_cityId][_buildingId] == 0, "Building in progress");
        uint[] memory cityBuildingLevels = Kingdoms.getCityBuildingsWithLevel(_cityId);
        (bool canBuild, ) = checkBuildingRequirementsMet(cityBuildingLevels, _buildingId);
        require(canBuild, "Building level requirements not met");
        uint[] memory resourceCost = getCostOfNextLevel(cityBuildingLevels, _buildingId);
        for (uint i = 0; i < resources.length; i++) {
            if (resourceCost[i] > 0) {
                IResourceToken(resources[i]).burnFrom(msg.sender, resourceCost[i]);
            }
        }
        uint timeCost = getNextLevelTimeRequirement(cityBuildingLevels, _buildingId);
        buildingQueue[msg.sender][_cityId][_buildingId] = block.timestamp + timeCost;
    }

    /** @notice levels up the building, collects resources for that city and updates the level in the resource manager */
    function completeLevelUpBuilding(uint _cityId, uint _buildingId) external {
        require(Kingdoms.getCityOwner(_cityId) == msg.sender, "Not owner of city");
        require(buildingQueue[msg.sender][_cityId][_buildingId] > 0 && buildingQueue[msg.sender][_cityId][_buildingId] < block.timestamp, "Level up not ready");
        ResourceManager.claimCityResources(_cityId);
        uint[] memory cityBuildingLevels = Kingdoms.getCityBuildingsWithLevel(_cityId);
        uint newLevel = cityBuildingLevels[_buildingId] + 1;
        Kingdoms.updateBuilding(_cityId, _buildingId, newLevel); 
        buildingQueue[msg.sender][_cityId][_buildingId] = 0;
        ResourceManager.setBuildingLevel(_cityId, _buildingId);
    }

    // Next three functions help calculate for building the next level building. They all have the same issue where a user could put in any info externally and get the wrong result
    // This isn't an issue for the levelup function. Can be fixed by created separate internal and external functions, where external pulls building levels
    /** @notice checks to see if buliding can be built 
        @param _cityBuildingLevels array of building levels to compare to requirements
        @return first bool is overall check, second array shows individual requirement check
        @dev The check can be manipulated by a user, but this is of no consequence
    */
    function checkBuildingRequirementsMet(uint[] memory _cityBuildingLevels, uint _buildingId) public view returns(bool, bool[] memory) {
        bool canBuild = true;
        bool[] memory levelRequirementMet = new bool[](buildingCount);
        for (uint i = 0; i < buildingCount; i++) {
            if (_cityBuildingLevels[i] >= buildingLevelRequirements[_buildingId][i]) {
                levelRequirementMet[i] = true;
            }
        }
        for(uint j = 0; j < buildingCount; j++) {
            if (levelRequirementMet[j] == false) {
                canBuild = false;
            }
        }
        return (canBuild, levelRequirementMet);
    }

    /** @notice returns resource cost of a building's next level
        @dev just like buliding requirements check, can be manipulated, but doesn't affect level up function */
    function getCostOfNextLevel(uint[] memory _cityBuildingLevels, uint _buildingId) public view returns(uint[] memory) {
        uint[] memory resourceCost = new uint[](resources.length); 
        for (uint i = 0; i < resources.length; i++) {
            resourceCost[i] = buildingResourceRequirements[_buildingId][i] * ((_cityBuildingLevels[_buildingId] + 1)**2);
        }
        return resourceCost;
    }

    /** @notice calculates the time (in seconds) to build the next level 
        @dev same miscalculation possible from external use*/
    function getNextLevelTimeRequirement(uint[] memory _cityBuildingLevels, uint _buildingId) public view returns(uint) {
        uint[] memory resourceCost = getCostOfNextLevel(_cityBuildingLevels, _buildingId);
        uint timeCost;
        for (uint i = 0; i < resources.length; i++) {
            timeCost += resourceCost[i] * i;
        }
        return timeCost;
    }

    function setKingdomContract(address _newContract) external onlyOwner {
        Kingdoms = IKingdoms(_newContract);
        emit NewKingdomsContract(_newContract);
    }

    function setResourceManagerContract(address _newContract) external onlyOwner {
        ResourceManager = IResourceManager(_newContract);
    }
}