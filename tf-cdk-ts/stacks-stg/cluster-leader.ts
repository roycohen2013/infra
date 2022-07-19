import { Construct } from 'constructs';
import { TerraformStack } from 'cdktf';
import {
  AzurermProvider,
  ResourceGroup,
  Subnet,
  VirtualNetwork
} from '@cdktf/provider-azurerm';

import { fiveLetterNames } from '../config/constant-strings';
import members from '../scripts/data/github-members.json';
import { createAzureRBACServicePrincipal } from '../config/service_principal';
import { StackConfigOptions } from '../components/remote-backend/index';
import { createVirtualMachine } from '../components/virtual-machine';

export default class stgClusterLeaderStack extends TerraformStack {
  constructor(
    scope: Construct,
    tfConstructName: string,
    config: StackConfigOptions
  ) {
    super(scope, tfConstructName);

    const { env, name } = config;

    const { subscriptionId, tenantId, clientId, clientSecret } =
      createAzureRBACServicePrincipal(this);

    new AzurermProvider(this, 'azurerm', {
      features: {},
      subscriptionId: subscriptionId.stringValue,
      tenantId: tenantId.stringValue,
      clientId: clientId.stringValue,
      clientSecret: clientSecret.stringValue
    });

    const rgIdentifier = `${env}-rg-${name}`;
    const rg = new ResourceGroup(this, rgIdentifier, {
      name: rgIdentifier,
      location: 'eastus'
    });

    const vnetIdentifier = `${env}-vnet-${name}`;
    const vnet = new VirtualNetwork(this, vnetIdentifier, {
      name: vnetIdentifier,
      resourceGroupName: rg.name,
      location: rg.location,
      addressSpace: ['10.0.0.0/16']
    });

    const subnetIdentifier = `${env}-subnet-${name}`;
    const subnet = new Subnet(this, subnetIdentifier, {
      name: subnetIdentifier,
      resourceGroupName: rg.name,
      virtualNetworkName: vnet.name,
      addressPrefixes: ['10.0.0.0/24']
    });

    const numberofControllers = 3;
    const nomadControllerServerNames = fiveLetterNames.slice(
      0,
      numberofControllers
    );

    const sshPublicKeys: Array<string> = [];
    members.map(member => {
      member?.publicKeys?.forEach(key => {
        sshPublicKeys.push(key);
      });
    });

    nomadControllerServerNames.map((serverName, index) => {
      createVirtualMachine(this, {
        stackName: name,
        vmName: serverName,
        rg: rg,
        env: env,
        size: 'Standard_D2s_v4',
        subnet: subnet,
        privateIP: '10.0.0.' + (10 + index),
        sshPublicKeys: sshPublicKeys,
        customImageId: `/subscriptions/${subscriptionId.stringValue}/resourceGroups/ops-rg-machine-images/providers/Microsoft.Compute/images/NOMAD-CONSUL-eastus-220718-1345`
      });
    });

    // End of stack
  }
}
