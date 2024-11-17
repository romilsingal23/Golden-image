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
      win_command: C:\Windows\System32\Sysprep\Sysprep.exe /generalize /oobe /quiet /mode:vm /quit /unattend:C:\ProgramData\Google\cloud-launcher\sysprep\Unattend.xml
      tags:
        - Windows_2016
        - Windows_2019

    - name: Setting up the instance for next startup (Shutdown)
      win_command: shutdown /s /t 0
      when: "'EBS_Windows_2019' in ansible_run_tags"
      args:
        chdir: C:\Program Files\Google\cloud-launcher
      tags:
        - EBS_Windows_2019

    - name: Setting up the instance for next startup (No Shutdown)
      win_command: powershell.exe -File "C:\Program Files\Google\cloud-launcher\InitializeInstance.ps1"
      when: "'Windows_2022' in ansible_run_tags"
      tags:
        - Windows_2022

    - name: "Sysprep Wait Time"
      pause:
        minutes: 5
      tags:
        - Windows_2016
        - Windows_2019

    - name: Make sure initialization script executes on next startup
      win_command: powershell.exe -
      args:
        stdin: C:\ProgramData\Google\cloud-launcher\scripts\InitializeInstance.ps1 –Schedule
      tags:
        - Windows_2016
        - Windows_2019
