-- Import required modules
local term = require("term")

-- Load configuration
local config = {}
local function loadConfig()
  local file = fs.open("mining_config.txt", "r")
  if file then
    local data = textutils.unserialize(file.readAll())
    file.close()
    if data then config = data end
  end
end

local function saveConfig()
  local file = fs.open("mining_config.txt", "w")
  if file then
    file.write(textutils.serialize(config))
    file.close()
  end
end

loadConfig()

-- Configuration with defaults
config.width = config.width or 16
config.length = config.length or 16
config.height = config.height or 5
config.chestSide = config.chestSide or "down"

-- Turtle information
local turtles = {
  {id = 1, x = 1, y = 1, z = 0, mining = false},
  {id = 2, x = config.width, y = 1, z = 0, mining = false},
  {id = 3, x = 1, y = config.length, z = 0, mining = false},
  {id = 4, x = config.width, y = config.length, z = 0, mining = false}
}
local currentTurtle = 1  -- ID of the current turtle

-- Mining status
local isMining = false
local currentLayer = 0
local totalOresMined = 0
local totalBlocksMined = 0
local startTime = 0

-- Ore selection
local selectedOres = {
  ["minecraft:coal_ore"] = true,
  ["minecraft:iron_ore"] = true,
  ["minecraft:gold_ore"] = true,
  ["minecraft:diamond_ore"] = true,
  ["minecraft:emerald_ore"] = true,
  ["minecraft:redstone_ore"] = true,
  ["minecraft:lapis_ore"] = true,
}

-- Function to check if a block is an ore
local function isOre(blockData)
  if blockData then
    if selectedOres[blockData.name] then
      return true
    end
    if string.find(blockData.name, "ore") or
       string.find(blockData.name, "crystal") or
       string.find(blockData.name, "gem") or
       string.find(blockData.name, "mineral") then
      return true
    end
  end
  return false
end

-- Function to detect chest side
local function detectChestSide()
  local sides = {"top", "bottom", "left", "right", "front", "back"}
  for _, side in ipairs(sides) do
    if peripheral.getType(side) == "minecraft:chest" then
      return side
    end
  end
  return "down"  -- Default if no chest found
end

-- Function to deposit items in the chest
local function depositItems()
  config.chestSide = detectChestSide()
  for slot = 1, 16 do
    turtle.select(slot)
    turtle.drop(config.chestSide)
  end
end

-- Fuel management
local function refuel()
  for slot = 1, 16 do
    turtle.select(slot)
    if turtle.refuel(0) then
      local fuelLevel = turtle.getFuelLevel()
      local needed = config.width * config.length * config.height - fuelLevel
      if needed > 0 then
        turtle.refuel(needed)
      end
      return true
    end
  end
  return false
end

local function checkFuel()
  local fuelLevel = turtle.getFuelLevel()
  if fuelLevel < config.width * config.length * config.height then
    print("Low fuel. Attempting to refuel...")
    if not refuel() then
      print("Out of fuel!")
      return false
    end
  end
  return true
end

-- Function for a single turtle to mine a layer
local function mineLayer(turtle)
  local startX, startY = turtle.x, turtle.y
  local endX = startX == 1 and config.width/2 or config.width
  local endY = startY == 1 and config.length/2 or config.length
  
  for y = startY, endY, startY < endY and 1 or -1 do
    for x = startX, endX, startX < endX and 1 or -1 do
      -- Update turtle position
      turtle.x, turtle.y = x, y
      
      -- Check and mine ores
      local function checkAndMine(inspectFunc, digFunc)
        local success, blockData = inspectFunc()
        if success then
          totalBlocksMined = totalBlocksMined + 1
          if isOre(blockData) then
            digFunc()
            totalOresMined = totalOresMined + 1
          end
        end
      end
      
      checkAndMine(turtle.inspect, turtle.dig)
      checkAndMine(turtle.inspectDown, turtle.digDown)
      checkAndMine(turtle.inspectUp, turtle.digUp)
      
      -- Move forward
      if x ~= endX then
        if not turtle.forward() then
          print("Path blocked at x:" .. x .. ", y:" .. y .. ", z:" .. turtle.z)
          return false
        end
      end
      
      -- Check inventory
      if turtle.getItemCount(16) > 0 then
        print("Inventory full, returning to deposit items")
        depositItems()
      end
    end
    
    -- Turn and move to the next row
    if y ~= endY then
      if (y - startY) % 2 == 0 then
        turtle.turnRight()
        if not turtle.forward() then
          print("Path blocked while turning")
          return false
        end
        turtle.turnRight()
      else
        turtle.turnLeft()
        if not turtle.forward() then
          print("Path blocked while turning")
          return false
        end
        turtle.turnLeft()
      end
    end
  end
  
  -- Return to start position
  turtle.x, turtle.y = startX, startY
  return true
end

-- Main mining function
local function mine(turtle)
  if not checkFuel() then
    print("Not enough fuel to complete mining operation.")
    return
  end

  turtle.mining = true
  for h = 1, config.height do
    currentLayer = h
    turtle.z = h - 1
    local success, err = pcall(function() 
      if not mineLayer(turtle) then
        error("Mining layer failed")
      end
    end)
    if not success then
      print("Error during mining: " .. err)
      turtle.mining = false
      return
    end
    
    -- Move down to the next layer
    if h < config.height then
      if not turtle.digDown() or not turtle.down() then
        print("Unable to move to next layer. Obstruction detected.")
        turtle.mining = false
        return
      end
    end
  end
  
  -- Return to surface
  for i = 1, config.height - 1 do
    if not turtle.up() then
      print("Unable to return to surface. Obstruction detected.")
      break
    end
  end
  turtle.z = 0
  
  -- Deposit items
  depositItems()
  
  currentLayer = 0
  turtle.mining = false
end

-- GUI functions
local function drawButton(x, y, width, text, active)
  term.setCursorPos(x, y)
  if active then
    term.setBackgroundColor(colors.lime)
    term.setTextColor(colors.black)
  else
    term.setBackgroundColor(colors.red)
    term.setTextColor(colors.white)
  end
  term.write(string.rep(" ", width))
  term.setCursorPos(x + math.floor((width - #text) / 2), y)
  term.write(text)
end

local function drawMap(startX, startY)
  for y = 1, config.length do
    term.setCursorPos(startX, startY + y - 1)
    for x = 1, config.width do
      local turtleHere = false
      for _, t in ipairs(turtles) do
        if t.x == x and t.y == y then
          term.setTextColor(t.mining and colors.lime or colors.red)
          term.write(t.id)
          turtleHere = true
          break
        end
      end
      if not turtleHere then
        term.setTextColor(colors.gray)
        term.write("·")
      end
    end
  end
end

local function drawGUI()
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  term.setTextColor(colors.white)
  term.write("Ore Mining Control")
  
  drawButton(2, 3, 10, "Start All", not isMining)
  drawButton(14, 3, 10, "Stop All", isMining)
  
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.setCursorPos(2, 5)
  term.write("Status: " .. (isMining and "Mining" or "Idle"))
  term.setCursorPos(2, 6)
  term.write("Current Layer: " .. currentLayer .. "/" .. config.height)
  term.setCursorPos(2, 7)
  term.write("Total Ores Mined: " .. totalOresMined)
  
  local elapsedTime = os.time() - startTime
  local oresPerHour = elapsedTime > 0 and math.floor(totalOresMined / (elapsedTime / 3600)) or 0
  term.setCursorPos(2, 8)
  term.write("Ores/Hour: " .. oresPerHour)
  
  term.setCursorPos(2, 10)
  term.write("Map:")
  drawMap(2, 11)
  
  term.setCursorPos(2, 12 + config.length)
  term.write("Legend: ")
  term.setTextColor(colors.red)
  term.write("■ ")
  term.setTextColor(colors.white)
  term.write("Idle ")
  term.setTextColor(colors.lime)
  term.write("■ ")
  term.setTextColor(colors.white)
  term.write("Mining")
end

-- Settings menu
local function settingsMenu()
  local settingsOptions = {
    "Width: " .. config.width,
    "Length: " .. config.length,
    "Height: " .. config.height,
    "Save and Exit"
  }
  local selected = 1
  
  local function drawSettingsMenu()
    term.clear()
    term.setCursorPos(1, 1)
    term.write("Settings Menu")
    for i, option in ipairs(settingsOptions) do
      term.setCursorPos(2, i + 2)
      if i == selected then
        term.write("> " .. option)
      else
        term.write("  " .. option)
      end
    end
  end
  
  while true do
    drawSettingsMenu()
    local event, key = os.pullEvent("key")
    if key == keys.up and selected > 1 then
      selected = selected - 1
    elseif key == keys.down and selected < #settingsOptions then
      selected = selected + 1
    elseif key == keys.enter then
      if selected == #settingsOptions then
        saveConfig()
        break
      else
        local value = tonumber(string.match(settingsOptions[selected], "%d+"))
        term.setCursorPos(2, #settingsOptions + 4)
        term.write("Enter new value: ")
        local input = tonumber(read())
        if input and input > 0 then
          if selected == 1 then config.width = input
          elseif selected == 2 then config.length = input
          elseif selected == 3 then config.height = input
          end
          settingsOptions[selected] = string.gsub(settingsOptions[selected], "%d+", tostring(input))
        end
      end
    end
  end
end

-- Main program loop
local function main()
  startTime = os.time()
  while true do
    drawGUI()
    local event, side, x, y = os.pullEvent("monitor_touch")
    
    if y == 3 then
      if x >= 2 and x <= 11 and not isMining then
        isMining = true
        startTime = os.time()
        for _, turtle in ipairs(turtles) do
          mine(turtle)
        end
        isMining = false
      elseif x >= 14 and x <= 23 and isMining then
        isMining = false
        for _, turtle in ipairs(turtles) do
          turtle.mining = false
        end
      end
    elseif y == config.length + 13 then
      settingsMenu()
    end
  end
end

-- Run the main program
main()
