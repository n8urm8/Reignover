// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./interfaces/IERC20.sol";
import "./libs/Editor.sol"; // editor modifier and OZ-Ownable
import "./interfaces/IBuilder.sol";

/** 
    @title The city management contract
    @author Nate F
    @notice Allows creation and transfering of cities. Allows creating new buildings and changing levels.
 */

// Setup: add Builder contract as an editor, set gameTokena and Builder contracts

contract Kingdom is Editor{

    IERC20 public gameToken; // this will be the premium currency, like gold
    IBuilder public Builder; // builder contract
    uint baseCityFee = 100*10**18; // 100 game tokens

    // City is the base structure in the game. They can be traded between players (taken over)
    struct City {
        string name;
        mapping(uint => uint) buildings; // building id to it's level
        bool primary;  // if primary, cannot transfer
    }
    City[] public cities; // ID list of cities
    mapping(uint => address) public cityIdToOwner; // connects city indices to wallets
    mapping(address => uint) public citiesPerOwner; // number of cities a wallet owns
    mapping(address => uint[]) public ownerCityList; // list of city Ids for a wallet
    // !!! City cap per player to limit eventual high gas fees? Is this needed?

    event CityCreated(uint cityId, string cityName, address indexed owner, uint cost);
    event CityTakeover(address indexed prevOwner, address indexed newOwner, uint cityId);
    event NameChange(uint indexed cityId, string newName);
    event NewBuildingLevel(uint indexed cityId, uint indexed buildingId, uint previousLevel, uint newLevel);
    event NewBuilderContract(address newContract);
    event NewGameTokenContract(address newcontract);

    modifier isCityOwner(uint _cityId) {
        require(msg.sender == cityIdToOwner[_cityId]);
        _;
    }

    /** @notice returns an array of building levels corresponding to the building index
    *    */
    function getCityBuildingsWithLevel(uint _cityId) external view returns(uint[] memory) {
        uint buildingCount = Builder.getBuildingCount();
        uint[] memory buildingList = new uint[](buildingCount);
        for (uint i = 0; i < buildingCount; i++) {
            buildingList[i] = cities[_cityId].buildings[i];
        }
        return buildingList;
    }

    function getCityScore(uint _cityId) external view returns(uint) {
        uint buildingCount = Builder.getBuildingCount();
        uint cityScore;
        for (uint i = 0; i < buildingCount; i++) {
            cityScore += cities[_cityId].buildings[i]**(1+i) ;
        }
        return cityScore;
    }

    function getCityOwner(uint _cityId) external view returns(address) {
        return cityIdToOwner[_cityId];
    }

    function getOwnerCities(address _owner) external view returns(uint[] memory) {
        return ownerCityList[_owner];
    }

    /** @notice creates a city for the sender
        @param _name sets the city's name
        @dev takes msg.sender value for the owner */
    function createCity(string memory _name) external {
        uint fee = ((citiesPerOwner[msg.sender] + 1)^2) * baseCityFee;
        // _payFee(fee);
        cities.push();
        cities[cities.length-1].name = _name;
        if (citiesPerOwner[msg.sender] == 0) {
            cities[cities.length-1].primary = true;
        }
        cityIdToOwner[cities.length-1] = msg.sender;
        citiesPerOwner[msg.sender]++;
        ownerCityList[msg.sender].push(cities.length-1);
        emit CityCreated(cities.length-1, _name, msg.sender, fee);
    }

    // need to think this through a bit. currently general fee payer function
    // probably change to burn
    function _payFee(uint _fee) internal {
        gameToken.transferFrom(msg.sender, address(this), _fee);
    }

    /** @notice used for city takeovers
        @param _cityId is the city id
        @param _newOwner is the address of the city's new owner
        @dev restricted to prevent unauthorized city tansfers  */
        // do I set this up as erc721? 
        // create a cost to the transfer so that a player can't get more cities for cheap by making new accounts
        // add a city cap per player?
    function cityTransfer(uint _cityId, address _newOwner) public onlyEditor {
        require(cities[_cityId].primary == false, "Cannot transfer primary");
        address oldOwner = cityIdToOwner[_cityId];
        for(uint i = 0; i < citiesPerOwner[oldOwner]; i++) {
            if(ownerCityList[oldOwner][i] == _cityId) {
                ownerCityList[oldOwner][i] = ownerCityList[oldOwner][citiesPerOwner[oldOwner]-1];
                ownerCityList[oldOwner].pop();
            }
        }
        ownerCityList[_newOwner].push(_cityId);
        cityIdToOwner[_cityId] = _newOwner;
        citiesPerOwner[oldOwner]--;
        citiesPerOwner[_newOwner]++;
        emit CityTakeover(oldOwner, _newOwner, _cityId);
    }

    /** @notice update a city name if you own it
        @param _cityId specific city
        @param _newName new name of the city
        @dev checks to make sure only city owner is changing name */
    function changeCityName(uint _cityId, string memory _newName) external isCityOwner(_cityId) {
        // add require/modifier for only city owner
        cities[_cityId].name = _newName;
        emit NameChange(_cityId, _newName);
    }

    /** @notice general function to change building levels for a city
        @dev are buildings managed externally or internally? */
    function updateBuilding(uint _cityId, uint _buildingId, uint _newBuildingLevel) external onlyEditor {
        uint prevLevel = cities[_cityId].buildings[_buildingId];
        cities[_cityId].buildings[_buildingId] = _newBuildingLevel;
        emit NewBuildingLevel(_cityId, _buildingId, prevLevel, _newBuildingLevel);
    }

    function setBuilderContract(address _newContract) external onlyOwner {
        Builder = IBuilder(_newContract);
        emit NewBuilderContract(_newContract);
    }

    function setGameTokenContract(address _newContract) external onlyOwner {
        gameToken = IERC20(_newContract);
        emit NewGameTokenContract(_newContract);
    }


}