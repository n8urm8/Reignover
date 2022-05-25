// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./ResourceToken.sol";
import "./libs/Editor.sol";
import "./interfaces/IBuilder.sol";
import "./interfaces/IKingdoms.sol";

// Setup: set Builder as editor of this contract, this contract also needs to be an editor of Builder

contract ResourceManager is Editor {

    ResourceToken[] public resourceTokens;
    IBuilder public Builder;
    IKingdoms public Kingdoms;
    
    struct RewardPool {
        uint buildingId;
        uint rewardToken;
        uint baseReward;
    }

    mapping(uint => RewardPool) public buildingToRewardPool; // get reward token of building
    mapping(uint => mapping(uint => uint)) cityBuildingLastClaim; // timestamp for the last time rewards were claimed for a building
    mapping(uint => mapping(uint => uint)) cityBuildingLevel; // records the building level for current reward cycle

    event UpdatedBuildingPool(uint buildingId, uint rewardToken, uint baseReward);
    event NewResource(address resourceToken, string name, string symbol);

    /** @notice creates a new ERC20 resource token and adds it to the Builder contract */
    function createResourceToken(string memory _name, string memory _symbol) external onlyOwner {
        ResourceToken resourceToken = new ResourceToken(_name, _symbol);
        resourceTokens.push(resourceToken);
        resourceToken.addEditor(address(this));
        Builder.addResource(address(resourceToken)); 
    }

    /** @notice sets the builder contract */
    function setBuilder(address _builder) external onlyOwner {
        Builder = IBuilder(_builder);
    }

    /** @notice sets the builder contract */
    function setKingdoms(address _kingdoms) external onlyOwner {
        Kingdoms = IKingdoms(_kingdoms);
    }

    /** @notice add an editor (minter) to a specific resource token */
    function resourceAddEditor(uint _resourceId, address _newEditor) external onlyOwner {
        resourceTokens[_resourceId].addEditor(_newEditor);
    }

    /** @notice remove an editor (minter) from a specific resource token */
    function resourceRemoveEditor(uint _resourceId, address _newEditor) external onlyOwner {
        resourceTokens[_resourceId].deactivateEditor(_newEditor);
    }

    // The next section manages the minting of tokens over time to cities depending on their building levels
    // This is similar to a standard farm contract, but instead of getting more rewards based on tokens staked, it's based on level of the building
    // When an appropriate building is created, it sets the reward start timestamp
    // Cities can change ownership, so rewards are city-owner agnostic in the way that they do not reset when ownership is changed

    /** @notice create a reward pool for a building, buildings only have one pool
        @param _baseReward base sure to write with 18 decimals in mind, set to 0 to turn off */
    function setRewardPool(uint _buildingId, uint _rewardtoken, uint _baseReward) external onlyOwner {
        buildingToRewardPool[_buildingId].buildingId = _buildingId;
        buildingToRewardPool[_buildingId].rewardToken = _rewardtoken;
        buildingToRewardPool[_buildingId].baseReward = _baseReward;
        emit UpdatedBuildingPool(_buildingId, _rewardtoken, _baseReward);
    }

    /** @notice function for starting the rewards timer of a building
        @dev comes from Builder contract upon completing a building level up */
    function updateLastClaimTime(uint _cityId, uint _buildingId) external onlyEditor {
        cityBuildingLastClaim[_cityId][_buildingId] = block.timestamp;
    }

    function setBuildingLevel(uint _cityId, uint _buildingId) external onlyEditor {
        uint[] memory cityBuildingLevels = Kingdoms.getCityBuildingsWithLevel(_cityId);
        cityBuildingLevel[_cityId][_buildingId] = cityBuildingLevels[_buildingId];
    }

    /** @notice mints built-up resources to city owner */
    function _claimCityResources(uint _cityId) internal {
        address cityOwner = Kingdoms.getCityOwner(_cityId);
        // do we care if non-city-owner calls this function?
        // require(msg.sender == cityOwner, "Must own city to claim"); 
        uint[] memory pendingRewards = getPendingCityRewards(_cityId);
        for(uint i = 0; i < pendingRewards.length; i++) {
            cityBuildingLastClaim[_cityId][i] = block.timestamp;
            if(pendingRewards[i] > 0) {
                resourceTokens[buildingToRewardPool[i].rewardToken].mint(cityOwner, pendingRewards[i]);
            }
        }
    }

    /** @notice user function to claim one city's pending resources */
    function claimCityResources(uint _cityId) external {
        _claimCityResources(_cityId);
    }

    /** @notice claims pending resources from all cities */
    function claimCityResourcesAll() external {
        uint[] memory cities = Kingdoms.getOwnerCities(msg.sender);
        for(uint i = 0; i < cities.length; i++) {
            _claimCityResources(cities[i]);
        }
    }

    /** @notice returns an array of pending resources for each building of a city */
    function getPendingCityRewards(uint _cityId) public view returns(uint[] memory) {
        uint[] memory cityBuildingLevels = Kingdoms.getCityBuildingsWithLevel(_cityId);
        uint[] memory pendingResources = new uint[](cityBuildingLevels.length);
        for(uint i = 0; i < cityBuildingLevels.length; i++) {
            pendingResources[cityBuildingLevels.length] = 
                ((cityBuildingLevels[i]**2) * buildingToRewardPool[i].baseReward * (block.timestamp - cityBuildingLastClaim[_cityId][i]) / 60);
        }
        return pendingResources;
    }

}