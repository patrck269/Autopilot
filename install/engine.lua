if fs.exists("startup.lua") then
  fs.delete("startup.lua")
end

print("The engine-room computer is not on the boot path.")
print("Fly from the command-center computer.")
os.reboot()
