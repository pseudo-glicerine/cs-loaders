--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Promise = require(ReplicatedStorage.Packages.Promise)

const IGNORED_MODULES_AND_DIRECTORIES = {}
const METHODS_TO_EXECUTE = {
	[1] = "Init",
	[2] = "Start",
}

const PREFIX = "[Client] "
const DEBUG_LEVEL = 0

const READY_ATTRIBUTE_NAME = "IsReady"

type ModuleName = string
type ModuleTable = {}

local Modules = script:GetDescendants()
local LoadedModules = {} :: { [ModuleName]: ModuleTable }

local function log(msg: string, debugLevel: number)
	if DEBUG_LEVEL >= debugLevel then
		print(PREFIX .. msg)
	end
end

local function checkModule(module: ModuleScript): boolean
	if not module:IsA("ModuleScript") then
		return false
	end

	-- // Check if the module is in the ignored list
	if table.find(IGNORED_MODULES_AND_DIRECTORIES, module.Name) then
		return false
	end

	-- // Check if one of the ignored directories is an ancestor of the module
	for _, ignoredDirectory in IGNORED_MODULES_AND_DIRECTORIES do
		if type(ignoredDirectory) == "string" then
			if module:FindFirstAncestor(ignoredDirectory) then
				return false
			end
		end

		if typeof(ignoredDirectory) == "Instance" then
			if module:IsDescendantOf(ignoredDirectory) then
				return false
			end
		end
	end

	return true
end

local function main()
	local modulesToLoad = {}
	for _, module: ModuleScript in Modules do
		if not checkModule(module) then
			continue
		end

		table.insert(modulesToLoad, module)
	end

	log("Module loading started", 1)

	-- // Cache all modules
	do
		local loadingPromises = {}

		for _, module: ModuleScript in modulesToLoad do
			local loadingPromise = Promise.new(function(resolve, reject)
				local success, cached = pcall(require, module)

				if success then
					resolve(cached)
				else
					reject(cached)
				end
			end)
				:andThen(function(cached)
					LoadedModules[module.Name] = cached
					log(`Loaded module: {module.Name}`, 1)
				end)
				:catch(function(err)
					log(`Failed to load module: {module.Name} - {tostring(err)}`, 1)
				end)

			table.insert(loadingPromises, loadingPromise)
		end

		Promise.all(loadingPromises):await()
	end

	-- // Execute methods on loaded modules
	for _, method in ipairs(METHODS_TO_EXECUTE) do
		local executionPromises = {}

		for moduleName, moduleTable in LoadedModules do
			if type(moduleTable) ~= "table" then
				continue
			end

			if type(moduleTable[method]) ~= "function" then
				continue
			end

			local methodExecutionPromise = Promise.new(function(resolve, reject)
				local success, result = pcall(moduleTable[method])
				if success then
					resolve(result)
				else
					reject(result)
				end
			end)
				:andThen(function()
					log(`Executed method: {method} in module: {moduleName}`, 1)
				end)
				:catch(function(err)
					log(`Failed to execute method: {method} in module: {moduleName} - {tostring(err)}`, 1)
				end)

			table.insert(executionPromises, methodExecutionPromise)
		end

		Promise.all(executionPromises):await()
	end
end

if not workspace:GetAttribute(READY_ATTRIBUTE_NAME) then
	workspace:GetAttributeChangedSignal(READY_ATTRIBUTE_NAME):Wait()
end

main()
