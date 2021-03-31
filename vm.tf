terraform {
  required_version = ">= 0.14"

  required_providers {
    azurerm = {
        source = "hashicorp/azurerm"
        version = ">= 2.26"
    }
  }
}

provider "azurerm" {
    skip_provider_registration = true
    features {}
}

 resource "azurerm_resource_group" "lab02" {
    name = "lab02"
    location = "eastus"
}

resource "azurerm_virtual_network" "lab02network" {
  name                = "lab02network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.lab02.location
  resource_group_name = azurerm_resource_group.lab02.name
}

resource "azurerm_subnet" "lab02subnetwork" {
  name                 = "lab02subnetwork"
  resource_group_name  = azurerm_resource_group.lab02.name
  virtual_network_name = azurerm_virtual_network.lab02network.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "lab02myip" {
  name                = "lab02myip"
  resource_group_name = azurerm_resource_group.lab02.name
  location            = azurerm_resource_group.lab02.location
  allocation_method   = "Static"

  tags = {
    environment = "Lab02Infra"
  }
}

resource "azurerm_network_interface" "lab02nic" {
  name                = "lab02nic"
  location            = azurerm_resource_group.lab02.location
  resource_group_name = azurerm_resource_group.lab02.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.lab02subnetwork.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.lab02myip.id
  }
}

resource "azurerm_network_security_group" "lab02sg" {
  name                = "lab02sg"
  location            = azurerm_resource_group.lab02.location
  resource_group_name = azurerm_resource_group.lab02.name

  security_rule {
    name                       = "SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    environment = "Lab02InfraSG"
  }
}

resource "azurerm_network_interface_security_group_association" "lab02sga" {
  network_interface_id      = azurerm_network_interface.lab02nic.id
  network_security_group_id = azurerm_network_security_group.lab02sg.id
}

resource "tls_private_key" "lab02privatessh" {
  algorithm   = "RSA"
  rsa_bits = 4096 
}

output tls_private_key {
  value = tls_private_key.lab02privatessh.private_key_pem
}

resource "azurerm_linux_virtual_machine" "lab02vm" {
  name                = "lab02vm"
  resource_group_name = azurerm_resource_group.lab02.name
  location            = azurerm_resource_group.lab02.location
  size                = "Standard_DS1_v2"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.lab02nic.id,
  ]

  admin_ssh_key {
    username   = "adminuser"
    public_key = tls_private_key.lab02privatessh.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
}

output "public_vm_ip" {
  value = azurerm_public_ip.lab02myip.ip_address
}

resource "null_resource" "upload_config_db" {
  provisioner "file" {
    connection {
      type        = "ssh"
      user        = "adminuser"
      host        = azurerm_public_ip.lab02myip.ip_address
      private_key = file("./key")
    }
    source = "~/mba/terraform/mysqld.cnf"
    destination = "/home/adminuser/mysqld.cnf"
  }  

  depends_on = [
    azurerm_linux_virtual_machine.lab02vm
  ]
}

resource "null_resource" "remote_exec_vm" {
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "adminuser"
      host        = azurerm_public_ip.lab02myip.ip_address
      private_key = file("./key")
    }
    inline = [ "sudo apt update",
               "sudo apt install -y mysql-server-5.7"
             ]
  }  

  depends_on = [
    null_resource.upload_config_db
  ]
}

