MATLAB analysis folder

Purpose:
Keep MATLAB scripts and copied CSV logs separate from the ComputerCraft files.

Workflow:
1. On the ComputerCraft experiment computer, collect data:
   collect_identification.lua auto 1 5 6 0.2 altitude_id.csv

2. Copy altitude_id.csv into this folder.

3. In MATLAB, set this folder as the current folder and run:
   matlab_identification

Files:
matlab_identification.m
  Reads altitude_id.csv or altitude_log.csv, plots the data, and runs tfest
  when System Identification Toolbox is available.
