local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Promise = require(ReplicatedStorage.Packages.Promise)

const MODULES_PATH = ReplicatedStorage.Client

const METHODS_TO_EXECUTE = {
	[1] = {
		Name = "Init",
		Parallel = false,
	},
} :: Methods
const IGNORED_DIRECTORIES = {}

const SERVER_READY_ATTRIBUTE = "ServerReady"
const AWAIT_SERVER = true

const PREFIX = "[Client]: "
const DEBUG_LEVEL = 0

type QueuePosition = number
type MethodName = string
type Methods = { [QueuePosition]: {
	Name: MethodName,
	Parallel: boolean,
} }

type ModuleName = string
type ModuleCache = {}

local LoadedModules = {} :: { [ModuleName]: ModuleCache }

local function log(msg: string, debugLevel: number, isWarn: boolean?)
	-- // Checks if provided debug level is higher than global DEBUG_LEVEL set
	if debugLevel > DEBUG_LEVEL then
		return
	end

	if not isWarn then
		print(PREFIX, msg)
	else
		warn(PREFIX, msg)
	end
end

local function getUnignoredModules()
	-- // Gets ignored modules (just all children of ignored directories actually)
	local ignored = {}
	for _, directory in IGNORED_DIRECTORIES do
		for _, module in directory:GetDescendants() do
			table.insert(ignored, module)
		end
	end

	local modules = {}
	for _, module in MODULES_PATH:GetDescendants() do
		if not module:IsA("ModuleScript") then
			continue
		end

		-- // Checks if module is in ignored list
		if table.find(ignored, module) then
			continue
		end

		modules[module.Name] = module
	end

	return modules
end

local function init()
	-- // Awaits server to finish loading
	if AWAIT_SERVER then
		if not workspace:GetAttribute(SERVER_READY_ATTRIBUTE) then
			workspace:GetAttributeChangedSignal(SERVER_READY_ATTRIBUTE):Wait()
		end
	end

	local modulesToLoad = getUnignoredModules()

	-- // Caches all available modules
	for moduleName, moduleInstance in modulesToLoad do
		local startTime = tick()
		local success, cachedOrError: ModuleCache = pcall(require, moduleInstance)
		if success then
			LoadedModules[moduleName] = cachedOrError

			local elapsed = tick() - startTime
			log(`Loaded module: {moduleName}. Time elapsed: {elapsed}`, 1)
		else
			log(`Error occured while trying to load module '{cachedOrError}'.\n{cachedOrError}`, 1)
		end
	end

	-- // Executes all methods on each loaded module
	for _, methodInfo in METHODS_TO_EXECUTE do
		local promises = {}
		for moduleName, moduleCache in LoadedModules do
			if type(moduleCache[methodInfo.Name]) ~= "function" then
				continue
			end

			local methodPromise = Promise.promisify(moduleCache[methodInfo.Name])(moduleCache)
				:andThen(function()
					log(`Successfully executed method '{methodInfo.Name}' of module: {moduleName}`, 2)
				end)
				:catch(function(message)
					log(
						`Error occured while trying to execute method '{methodInfo.Name}' of module: {moduleName}\n{message}`,
						2
					)
				end)

			table.insert(promises, methodPromise)

			if methodInfo.Parallel then
				methodPromise:await()
			end
		end

		Promise.all(promises):await()
	end
end

init()
