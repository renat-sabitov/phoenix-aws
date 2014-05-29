
Baking with packer
===

To learn more refer to: <https://confluence.sirca.org.au/confluence/display/SIRPROC/Complete+baking+solution%3A+Packer+plus+Ansible>

Requirements
===

* `packer` version > 0.6  <https://github.com/mitchellh/packer>
* `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` environment variables set or an instance with appropriate IAM role

Bootstrapping
===

1. Launch an Amazon Linux instance 

2. Install `ansible` locally

3. Configure an inventory file `inventory`:

        [localhost]
        <instance public IP>

4. provision `packer` using `ansible`
	ansible-playbook -i inventory -e sirca_role=bakery ansible/one_role.yml

5. The instance is ready to bake, clone git repo on the instance and use commands below to bake images

Image naming conventions
===

Baked images have the following name structure:

`<image_name>_<version>`

where `image_name` and `version` are parameters passed to packer

`image_name` should be the same as ansible role

Baking Bakery
===

    packer build  -var version=$(date +%Y%m%d%H%M) -var base_ami=<Amazon Linux 64bit EBS AMI> -var image_name=bakery base.json

Baking Sirca Linux and nat images
===

    packer build  -var version=$(date +%Y%m%d%H%M) -var base_ami=<Amazon Linux 64bit EBS AMI> -var image_name=sirca_linux base.json
    packer build  -var version=$(date +%Y%m%d%H%M) -var base_ami=<Amazon NAT 64bit EBS AMI> -var image_name=nat base.json

Baking SELinux image
===

    packer build  -var version=$(date +%Y%m%d%H%M) -var base_ami=<Sirca_Linux ami id>  selinux.json
