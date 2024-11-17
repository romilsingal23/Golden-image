
- hosts: all
  gather_timeout: 100
  gather_facts: yes

- hosts: all
  gather_facts: no
  roles:
    - common

- hosts: all
  gather_facts: no
  roles:
    - win2022-cis
  tags:
    - Windows_2022

- hosts: all
  gather_facts: no
  roles:
    - win2019-cis
  tags:
    - Windows_2019
    - EBS_Windows_2019

- hosts: all
  gather_facts: no
  roles:
    - win2016-cis
  tags:
    - Windows_2016

- hosts: all
  gather_facts: no
  roles:
    - inspector
  tags:
    - always


- hosts: all
  tasks:
  - name: "Sysprep VM"
    win_command: C:\Windows\System32\Sysprep\Sysprep.exe /generalize /oobe /quiet /mode:vm /quit /unattend:C:\ProgramData\amazon\ec2-windows\launch\sysprep\Unattend.xml
  tags:
    - Windows_2016
    - Windows_2019

- hosts: all
  tasks:
  - name: setting up the instance for next start up
    win_command: .\EC2Launch.exe sysprep --shutdown=true
    args:
      chdir: C:\Program Files\Amazon\EC2Launch
  tags:
    - EBS_Windows_2019

- hosts: all
  tasks:
  - name: setting up the instance for next start up
    win_command: .\EC2Launch.exe sysprep --shutdown=false
    args:
      chdir: C:\Program Files\Amazon\EC2Launch
  tags:
    - Windows_2022

- hosts: all
  tasks:
  - name: "Sysprep Wait Time"
    pause:
      minutes: 5
  tags:
    - Windows_2016
    - Windows_2019

- hosts: all
  tasks:
  - name: make sure initialisation script executes on next startup
    win_command: powershell.exe -
    args:
      stdin: C:\ProgramData\Amazon\EC2-Windows\Launch\Scripts\InitializeInstance.ps1 –Schedule
  tags:
    - Windows_2016
    - Windows_2019

