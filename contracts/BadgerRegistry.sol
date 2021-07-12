// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.6.0 <0.7.0;
pragma experimental ABIEncoderV2;

interface VaultView {
  function name() external view returns (string memory);
  function symbol() external view returns (string memory);

  function token() external view returns (address);

  function pendingGovernance() external view returns (address);
  function governance() external view returns (address);
  function management() external view returns (address);
  function guardian() external view returns (address);

  function rewards() external view returns (address);

  function withdrawalQueue(uint256 index) external view returns (address);
}

interface StratView {
    function name() external view returns (string memory);

    function strategist() external view returns (address);
    function rewards() external view returns (address);
    function keeper() external view returns (address);

}


contract BadgerRegistry {
  // Multisig. Vaults from here are considered Production ready
  address GOVERNANCE = 0xB65cef03b9B89f99517643226d76e286ee999e77;

  // Given an Author Address, and Token, Return the Vault
  mapping(address => address[]) public vaults;

  event NewVault(address author, address vault);
  event RemoveVault(address author, address vault);
  event PromoteVault(address author, address vault);

  // Data from Vault
  struct StrategyParams {
    uint256 performanceFee;
    uint256 activation;
    uint256 debtRatio;
    uint256 minDebtPerHarvest;
    uint256 maxDebtPerHarvest;
    uint256 lastReport;
    uint256 totalDebt;
    uint256 totalGain;
    uint256 totalLoss;
    bool enforceChangeLimit;
    uint256 profitLimitRatio;
    uint256 lossLimitRatio;
    address customCheck;
  }

  // View Data for each strat we will return
  struct StratInfo {
    string name;

    address strategist;
    address rewards;
    address keeper;

    // uint256 performanceFee;
    // uint256 activation;
    // uint256 debtRatio;
    // uint256 minDebtPerHarvest;
    // uint256 maxDebtPerHarvest;
    // uint256 lastReport;
    // uint256 totalDebt;
    // uint256 totalGain;
    // uint256 totalLoss;
    // bool enforceChangeLimit;
    // uint256 profitLimitRatio;
    // uint256 lossLimitRatio;
    // address customCheck;
  }

  // Vault data we will return for each Vault
  struct VaultInfo {
    string name;
    string symbol;

    address token;

    address pendingGovernance; // If this is non zero, this is an attack from the deployer
    address governance;
    address guardian;
    address management;
    address rewards;

    StratInfo[] strategies;
  }



  // Anyone can add a vault to here
  function add(address vault) public {
    vaults[msg.sender].push(vault);
    
    emit NewVault(msg.sender, vault);
  }

  function remove(address vault) public {
    address[] storage list = vaults[msg.sender];
    uint256 length = list.length;
    uint256 index = length; // Index can only be up to length - 1. If index if lenght, we didn't find it
    
    for(uint256 x; x < length; x++){
      if(list[x] == vault){
        index = x;
      }
    }

    if(index != length) {
      list[index] = list[list.length - 1];
      list.pop();
    }

    emit RemoveVault(msg.sender, vault);
  }

  function fromAuthor(address author) public view returns (address[] memory) {
    address[] memory list = vaults[msg.sender];
    return list;
  }

  function fromAuthorVaults(address author) public view returns (VaultInfo[] memory) {
    address[] memory list = vaults[msg.sender];
    VaultInfo[] memory vaultData = new VaultInfo[](list.length);
    for(uint x = 0; x < list.length; x++){
      VaultView vault = VaultView(list[x]);
      StratInfo[] memory allStrats = new StratInfo[](0);

      VaultInfo memory data = VaultInfo({
        name: vault.name(),
        symbol: vault.symbol(),
        token: vault.token(),
        pendingGovernance: vault.pendingGovernance(),
        governance: vault.governance(),
        rewards: vault.rewards(),
        guardian: vault.guardian(),
        management: vault.management(),
        strategies: allStrats
      });

      vaultData[x] = data;
    }
  }

  
  // Given one Author, retrieve all their vaults and the strats associated with them
  function fromAuthorWithDetails(address author) public view returns (VaultInfo[] memory) {
    address[] memory list = vaults[msg.sender];
    VaultInfo[] memory vaultData = new VaultInfo[](list.length);
    
    for(uint x = 0; x < list.length; x++){
      VaultView vault = VaultView(list[x]);

      // TODO: Strat Info with real data
      uint stratCount = 0;
      for(uint y = 0; y < 20; y++){
        if(vault.withdrawalQueue(y) != address(0)){
          stratCount++;
        }
      }
      StratInfo[] memory allStrats = new StratInfo[](stratCount);

      for(uint z = 0; z < stratCount; z++){
        StratView strat = StratView(vault.withdrawalQueue(z));
        StratInfo memory stratData = StratInfo({
          name: strat.name(),
          strategist: strat.strategist(),
          rewards: strat.rewards(),
          keeper: strat.keeper()
        });
        allStrats[z] = stratData;
      }

      VaultInfo memory data = VaultInfo({
        name: vault.name(),
        symbol: vault.symbol(),
        token: vault.token(),
        pendingGovernance: vault.pendingGovernance(),
        governance: vault.governance(),
        rewards: vault.rewards(),
        guardian: vault.guardian(),
        management: vault.management(),
        strategies: allStrats
      });

      vaultData[x] = data;
    }

    return vaultData;
  }

  // Promote a vault to Production
  function promote(address vault) public {
    // TODO: Add security checks
    require(msg.sender == GOVERNANCE, "!gov");
    vaults[msg.sender].push(vault);

    emit PromoteVault(msg.sender, vault);
  }
}