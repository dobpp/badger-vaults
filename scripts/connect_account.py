from pathlib import Path
import yaml
import click

from brownie import Token, Vault, AdminUpgradeabilityProxy, accounts, network, web3
from eth_utils import is_checksum_address
from semantic_version import Version

def connect_account():
    click.echo(f"You are using the '{network.show_active()}' network")
    dev = accounts.load(click.prompt("Account", type=click.Choice(accounts.load())))
    click.echo(f"You are using: 'dev' [{dev.address}]")
    return dev