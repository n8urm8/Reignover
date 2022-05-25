// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./libs/Editor.sol";
import "./interfaces/IKingdoms.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IResourceManager.sol";

// Setup: set ResourceManager as editor of this contract, this contract also needs to be an editor of ResourceManager
// set Kingdoms, ResourceManager contract

contract Research is Editor {

    IKingdoms public Kingdoms; // Kingdoms Contract    
    IResourceManager public ResourceManager; // ResourceManager contract
    address[] public resources; // list of resource tokens
    uint researchCount; // count of active research
    mapping(uint => string) public researchIdToName; // may need to determine the best way to handle the research list
    mapping(uint => mapping(uint => uint)) researchLevelRequirements; // maps research with required research + level
    mapping(uint => mapping(uint => uint)) researchResourceRequirements; // base resources required to build
    mapping(uint => uint) researchMaxLevel;
    // wallet > cityId > researchId > time until ready
    mapping(address => mapping(uint => mapping(uint => uint))) public researchQueue; 

    event NewResource(uint id, address resource);
    event NewResearchLevelRequirements(uint indexed researchId, uint[] levelRequirements);
    event NewResearchResourceRequirements(uint indexed researchId, uint[] resourceRequirements);
    event NewResearchMaxLevel(uint indexed researchId, uint maxLevel);
    event ResearchCreated(uint researchId, string researchName);
    event NewResearchName(uint indexed researchId, string newResearchName);
    event NewKingdomsContract(address newContract);

    /** 
        @notice creates a new research for cities
        @param _name is the name of the new research
        @param _levelRequirements is array of research's required research levels, length should include research we are adding
        @param _resourceRequirements is array of research required resources, length should include research we are adding, 18 decimals
        @param _maxLevel is max level research can be built
        @dev params can be edited later on if needed
    */ 
    function addResearch(string memory _name, uint[] memory _levelRequirements, uint[] memory _resourceRequirements, uint _maxLevel ) external onlyOwner {
        researchIdToName[researchCount] = _name;
        emit ResearchCreated(researchCount, _name);
        researchCount++;
        uint _researchId = researchCount-1;
        _setResearchLevelRequirements(_researchId, _levelRequirements);
        _setResearchResourceRequirements(_researchId, _resourceRequirements);
        _setResearchMaxLevel(_researchId, _maxLevel);
    }

    /** @notice returns array of research */
    function getResearch() external view returns(string[] memory) {
        string[] memory researchList = new string[](researchCount);
        for (uint i = 0; i < researchCount; i++) {
            researchList[i] = researchIdToName[i];
        }
        return researchList;
    }

    function getResearchCount() external view returns(uint) {
        return researchCount;
    }
    
    /** @notice owner can modify the level requirements of other research to be able to build a research
        @dev can only use for research that already exist
    */
    function setResearchLevelRequirements(uint _researchId, uint[] memory _requirements) public onlyOwner {
        require(_researchId < researchCount, "research not active");
        _setResearchLevelRequirements( _researchId, _requirements);
    }
    
    /** @notice internal function to set research level requirements during creation
        @param _researchId research to update
        @param _requirements array index is the researchID, index value is level required 
    */
    function _setResearchLevelRequirements(uint _researchId, uint[] memory _requirements) internal {
        require(_requirements.length == researchCount, "array length mismatch"); 
        require(_requirements[_researchId] == 0, "cannot require self");
        for (uint i=0; i < researchCount; i++) {
            researchLevelRequirements[_researchId][i] = _requirements[i];
        }
        emit NewResearchLevelRequirements(_researchId, _requirements);
    }

    /** @notice owner can modify the resource requirements of research
        @param _requirements remember 18 decimals for token amount
        @dev can only use for research that already exist
    */
    function setResearchResourceRequirements(uint _researchId, uint[] memory _requirements) public onlyOwner {
        require(_researchId < researchCount, "research not active");
        _setResearchResourceRequirements( _researchId, _requirements);
    }

    /** @notice internal function to set research resource requirements during creation
        @param _researchId research to update
        @param _requirements array index is the resource, index value is amount required 
    */
    function _setResearchResourceRequirements(uint _researchId, uint[] memory _requirements) internal {
        require(_requirements.length == resources.length, "array length mismatch");
        require(_requirements[0] == 0, "cannot require base token");
        for (uint i=0; i < resources.length; i++) {
            researchResourceRequirements[_researchId][i] = _requirements[i];
        }
        emit NewResearchResourceRequirements(_researchId, _requirements);
    }

    function setResearchMaxLevel(uint _researchId, uint _maxLevel) external onlyOwner {
        _setResearchMaxLevel(_researchId, _maxLevel);
    }

    /** @notice sets max level for a research */
    function _setResearchMaxLevel(uint _researchId, uint _maxLevel) internal {
        researchMaxLevel[_researchId] = _maxLevel;
        emit NewResearchMaxLevel(_researchId, _maxLevel);
    }

    function setResearchName(uint _researchId, string memory _newName) external onlyOwner {
        researchIdToName[_researchId] = _newName;
        emit NewResearchName(_researchId, _newName);
    }

    /** @notice used by resource manager when creating a new resource token
        @dev preservation of order of resources is critically important, 
        allows resources to be added in by any editor in case this contract is replaced
    */
    function addResource(address _resourceAddress) external onlyEditor {
        resources.push(_resourceAddress);
        emit NewResource(resources.length-1, _resourceAddress);
    }

    /** @notice only to be used if a token needs to be replaced */
    function editResource(uint _id, address _newAddress) external onlyOwner {
        resources[_id] = _newAddress;
        emit NewResource(_id, _newAddress);
    }

    function getResourceCount() external view returns(uint) {
        return resources.length;
    }

    /** @notice starts research the next level of a research if all requirements met
        @dev pulls research data from Kingdoms contract
    */

    // Create mapping to hold a user's research levels
    function prepLevelUpResearch(uint _cityId, uint _researchId) external {
        require(Kingdoms.getCityOwner(_cityId) == msg.sender, "Not owner of city");
        require(researchQueue[msg.sender][_cityId][_researchId] == 0, "Research in progress");
        // uint[] memory cityResearchLevels = Kingdoms.getCityResearchWithLevel(_cityId); // replace with research levels from this contract
        uint[] memory cityResearchLevels;
        (bool canBuild, ) = checkResearchRequirementsMet(cityResearchLevels, _researchId);
        require(canBuild, "Research level requirements not met");
        uint[] memory resourceCost = getCostOfNextLevel(cityResearchLevels, _researchId);
        for (uint i = 0; i < resources.length; i++) {
            if (resourceCost[i] > 0) {
                IERC20(resources[i]).burnFrom(msg.sender, resourceCost[i]);
            }
        }
        uint timeCost = getNextLevelTimeRequirement(cityResearchLevels, _researchId);
        researchQueue[msg.sender][_cityId][_researchId] = block.timestamp + timeCost;
    }

    /** @notice levels up the research, collects resources for that city and updates the level in the resource manager */
    function completeLevelUpResearch(uint _cityId, uint _researchId) external {
        require(Kingdoms.getCityOwner(_cityId) == msg.sender, "Not owner of city");
        require(researchQueue[msg.sender][_cityId][_researchId] > 0 && researchQueue[msg.sender][_cityId][_researchId] < block.timestamp, "Level up not ready");
        // ResourceManager.claimCityResources(_cityId); // probably good to keep this in here
        // uint[] memory cityResearchLevels = Kingdoms.getCityResearchWithLevel(_cityId); // replace with research levels from this contract
        uint[] memory cityResearchLevels;
        uint newLevel = cityResearchLevels[_researchId] + 1;
        // Kingdoms.updateResearch(_cityId, _researchId, newLevel); // replace with research levels here
        researchQueue[msg.sender][_cityId][_researchId] = 0;
        // ResourceManager.setResearchLevel(_cityId, _researchId); // create function in resourceManager that allows research to increase resources?
    }

    // Next three functions help calculate for research the next level research. They all have the same issue where a user could put in any info externally and get the wrong result
    // This isn't an issue for the levelup function. Can be fixed by created separate internal and external functions, where external pulls research levels
    /** @notice checks to see if buliding can be built 
        @param _cityResearchLevels array of research levels to compare to requirements
        @return first bool is overall check, second array shows individual requirement check
        @dev The check can be manipulated by a user, but this is of no consequence
    */
    function checkResearchRequirementsMet(uint[] memory _cityResearchLevels, uint _researchId) public view returns(bool, bool[] memory) {
        bool canBuild = true;
        bool[] memory levelRequirementMet = new bool[](researchCount);
        for (uint i = 0; i < researchCount; i++) {
            if (_cityResearchLevels[i] >= researchLevelRequirements[_researchId][i]) {
                levelRequirementMet[i] = true;
            }
        }
        for(uint j = 0; j < researchCount; j++) {
            if (levelRequirementMet[j] == false) {
                canBuild = false;
            }
        }
        return (canBuild, levelRequirementMet);
    }

    /** @notice returns resource cost of a research's next level
        @dev just like buliding requirements check, can be manipulated, but doesn't affect level up function */
    function getCostOfNextLevel(uint[] memory _cityResearchLevels, uint _researchId) public view returns(uint[] memory) {
        uint[] memory resourceCost = new uint[](resources.length); 
        for (uint i = 0; i < resources.length; i++) {
            resourceCost[i] = researchResourceRequirements[_researchId][i] * ((_cityResearchLevels[_researchId] + 1)**2);
        }
        return resourceCost;
    }

    /** @notice calculates the time (in seconds) to build the next level 
        @dev same miscalculation possible from external use*/
    function getNextLevelTimeRequirement(uint[] memory _cityResearchLevels, uint _researchId) public view returns(uint) {
        uint[] memory resourceCost = getCostOfNextLevel(_cityResearchLevels, _researchId);
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