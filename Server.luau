local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Promise = require(ReplicatedStorage.Packages.Promise)

local INIT_AND_START_IGNORE = {}
local PREFIX = "[Server]: "
local LOGGING_ENABLED = true
local LOG_LEVEL = 1

local LoadedModules = {}

local function log(msg: any, logLevel: number)
	if LOGGING_ENABLED ~= true then
		return
	end

	if LOG_LEVEL < logLevel then
		return
	end

	print(PREFIX, msg)
end

function InitAndStartLoadedModules()
	local function promiseModuleMethod(moduleInstance: ModuleScript, moduleCache: {}, methodName: string)
		if typeof(moduleCache[methodName]) ~= "function" then
			return nil
		end

		return Promise.new(function(resolve, reject)
			log(`{moduleInstance.Name} | {methodName} | [?]`, 3)
			local success, errorMsg = pcall(moduleCache[methodName], moduleCache)
			log(`{moduleInstance.Name} | {methodName} | [+]`, 3)

			if not success then
				reject(errorMsg)
				return
			end

			resolve()
		end)
			:andThen(function()
				log(`{methodName}ed {moduleInstance.Name}`, 3)
			end)
			:catch(function(errorMsg: string)
				log(`Not {methodName}ed {moduleInstance.Name}. Error: {errorMsg}`, 3)
			end)
	end

	local function getUnignoreModules()
		if table.maxn(INIT_AND_START_IGNORE) == 0 then
			return LoadedModules
		end

		local unignoreModules = {}
		for moduleInstance, moduleCache in LoadedModules do
			local ignore = false
			for _, ignoreModuleOrFolder in INIT_AND_START_IGNORE do
				if moduleInstance:IsDescendantOf(ignoreModuleOrFolder) then
					ignore = true
					break
				end

				if moduleInstance == ignoreModuleOrFolder then
					ignore = true
					break
				end
			end

			if not ignore then
				unignoreModules[moduleInstance] = moduleCache
			end
		end

		return unignoreModules
	end

	local function initModules()
		local initPromises = {}

		for moduleInstance, moduleCache in getUnignoreModules() do
			if type(moduleCache) ~= "table" then
				continue
			end

			local initPromise = promiseModuleMethod(moduleInstance, moduleCache, "Init")
			if not initPromise then
				continue
			end

			table.insert(initPromises, initPromise)

			log(`{#initPromises}`, 3)
		end

		log(initPromises, 3)

		Promise.all(initPromises):await()
	end

	local function startModules()
		local startPromises = {}

		for moduleInstance, moduleCache in getUnignoreModules() do
			if type(moduleCache) ~= "table" then
				continue
			end

			local startPromise = promiseModuleMethod(moduleInstance, moduleCache, "Start")
			if not startPromise then
				continue
			end

			table.insert(startPromises, startPromise)

			log(`{#startPromises}`, 3)
		end

		log(startPromises, 3)

		Promise.all(startPromises):await()
	end

	Promise.promisify(initModules)():await()
	Promise.promisify(startModules)():await()
end

function LoadModules()
	local function attemptRequire(module: ModuleScript)
		return Promise.new(function(resolve, reject)
			local success, cached = pcall(require, module)

			if success then
				resolve(cached)
			else
				reject()
			end
		end)
	end

	local requirePromises = {}
	for _, module in script:GetDescendants() do
		if module:IsA("ModuleScript") then
			local sTime = tick()
			table.insert(
				requirePromises,
				attemptRequire(module)
					:andThen(function(cached: {})
						LoadedModules[module] = cached
						log(`Successfully loaded module "{module.Name}"! Time elapsed: {tick() - sTime}`, 1)
					end)
					:catch(function(errorMsg: string)
						log(`Error occured while trying to require module "{module.Name}": {errorMsg}`, 1)
					end)
			)
		end
	end

	log(requirePromises, 3)
	Promise.all(requirePromises):await()
end

LoadModules()
InitAndStartLoadedModules()

workspace:SetAttribute("IsReady", true)
