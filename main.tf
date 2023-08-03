resource "random_pet" "rg_name" {
  prefix = var.resource_group_name_prefix
}

resource "azurerm_resource_group" "rg" {
  location = var.resource_group_location
  name     = random_pet.rg_name.id
}

# Create virtual network
resource "azurerm_virtual_network" "terraform_network" {
  name                = "Vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Create subnet
resource "azurerm_subnet" "terraform_subnet" {
  name                 = "Subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.terraform_network.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Create public IPs
resource "azurerm_public_ip" "public_ip" {
  count               = 2
  name                = "PublicIP${count.index + 1}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
}

# get data 
data "azurerm_public_ip" "public_ips" {
  count               = 2
  name                = "${element(azurerm_public_ip.public_ip.*.name, count.index)}"
  resource_group_name = "${azurerm_resource_group.rg.name}"  # Use "rg" instead of "public_ip"
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "terraform_nsg" {
  name                = "NetworkSecurityGroup"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Associate public IPs with network interfaces of virtual machines
resource "azurerm_network_interface" "terraform_nic" {
  count               = 2
  name                = "NIC${count.index + 1}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "nic_configuration${count.index + 1}"
    subnet_id                     = azurerm_subnet.terraform_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip[count.index].id
  }
}

# Connect the security group to the network interfaces
resource "azurerm_network_interface_security_group_association" "example" {
  count                   = 2
  network_interface_id    = azurerm_network_interface.terraform_nic[count.index].id
  network_security_group_id = azurerm_network_security_group.terraform_nsg.id
}

# Generate random text for unique storage account names
resource "random_id" "random_id" {
  count = 2

  keepers = {
    resource_group = azurerm_resource_group.rg.name
  }

  byte_length = 8
}

# Create storage accounts for boot diagnostics
resource "azurerm_storage_account" "storage_account" {
  count                   = 2
  name                    = "diag${random_id.random_id[count.index].hex}"
  location                = azurerm_resource_group.rg.location
  resource_group_name     = azurerm_resource_group.rg.name
  account_tier            = "Standard"
  account_replication_type = "LRS"
}

# creating cloud init scripts
data "template_cloudinit_config" "vm" {
  gzip          = true
  base64_encode = true

 part {
    content_type = "text/cloud-config"
    content = <<EOF
    package_update: true
    package_upgrade: true
    packages:
      - vim
      - python3
      - python3-pip
    EOF
  }

  part {
    content_type = "text/cloud-config"
    content = <<EOF
    write_files:
      - path: /root/vm_info.txt
        content: |
          VM
        owner: root
        permissions: '0644'
    EOF
  }

}

data "template_file" "ansible_test_playbook" {
    template = file("${path.module}/ansible-test/connection_test.yml")
}

data "template_cloudinit_config" "ansible" {
  gzip          = true
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content = <<EOF
    package_update: true
    package_upgrade: true
    packages:
      - vim
      - python3
      - python3-pip
      - git
    EOF
  }

  part {
    content_type = "text/cloud-config"
    content = <<EOF
    ansible:
      package_name: ansible-core
      install_method: pip
    EOF
  }

  part {
  content_type = "text/cloud-config"
  content = <<EOF
    runcmd:
      - cd
      - sudo ansible-galaxy collection install community.general
      - git clone https://github.com/fl028/nodejsapp-demo.git
    EOF
  }

  part {
  content_type = "text/cloud-config"
  content = <<EOF
    write_files:
    - path: /root/vm_info.txt
      content: |
        Ansible Controller
      owner: root
      permissions: '0644'
    - path: /root/private_key.pem
      owner: root
      permissions: '0400'
      content: |
        ${indent(8, local.private_key_content)}
    - path: /root/ansible/hosts
      owner: root
      permissions: '0644'
      content: |
        [web-servers]
        ${element(azurerm_network_interface.terraform_nic.*.private_ip_address, 0)} ansible_user=azureadmin ansible_ssh_private_key_file=/root/private_key.pem
    - path: /root/ansible/playbooks/connection_test.yml
      owner: root
      permissions: '0644'
      content: |
        ${indent(10, data.template_file.ansible_test_playbook.rendered)}
    EOF
  }
}

# Create virtual machines
resource "azurerm_linux_virtual_machine" "terraform_vm" {
  count                  = 2
  name                   = "vm${count.index + 1}"
  location               = azurerm_resource_group.rg.location
  resource_group_name    = azurerm_resource_group.rg.name
  network_interface_ids  = [azurerm_network_interface.terraform_nic[count.index].id]
  size                   = "Standard_B1ls"

  custom_data = count.index == 0 ? data.template_cloudinit_config.vm.rendered : data.template_cloudinit_config.ansible.rendered

  os_disk {
    name                 = "osdisk${count.index + 1}"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  computer_name  = "vm${count.index + 1}"
  admin_username = var.username

  admin_ssh_key {
    username   = var.username
    public_key = jsondecode(azapi_resource_action.ssh_public_key_gen.output).publicKey
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.storage_account[count.index].primary_blob_endpoint
  }
}

# Output variables to display the SSH commands and ips
output "ssh_command_vm1"{
  value = "ssh -i ./private_key.pem azureadmin@${azurerm_public_ip.public_ip[0].ip_address}"
}

output "ssh_command_vm2"{
  value = "ssh -i ./private_key.pem azureadmin@${azurerm_public_ip.public_ip[1].ip_address}"
}

output "debug-cloud-init"{
  value = "${data.template_cloudinit_config.ansible.rendered}"
}




 

