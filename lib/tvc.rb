require 'rubygems'
require 'digest/sha2'
require 'fileutils'
require 'json'
require 'tmpdir'
require 'diff/lcs'
require 'zlib'

class Diff::LCS::Change
	attr_accessor :position
end

class TVC
	# print an error that states that the program must be run in the directory
	# with the repository, and that the repository needs to be initialized.
	#
	# this was a commonly used error, hence the function just for it.
	def repositoryIssueError
		puts "The repository either has not been initialized 
			or this command is not being run from the base
			directory of the repository".gsub(/\s+/, " ").strip
	end

	# initialize a repository
	def init
		Dir.chdir(@runDir)
		Dir.mkdir(".tvc") unless Dir::exists?(".tvc")
		@repoDir = getRepositoryDirectory
		Dir.mkdir(getObjectsDirectory) unless Dir::exists?(getObjectsDirectory)
		saveDataToJson(File.join(@repoDir, "pointers"), [{"name" => "master", "hash" => nil, "parent" => nil}])
		saveDataToJson(File.join(@repoDir, "history"), [])
		saveDataToJson(File.join(@repoDir, "current"), [{"name" => "master", "hash" => nil, "parent" => nil}])
	end

	# commit current changes
	def commit(message)
		hash = createObjects(@runDir)
		current = getCurrentEntry
		data = {"message" => message, "hash" => hash, "parent" => current["hash"]}
		addHistoryEntry(data)
		current["parent"] = data["parent"]
		current["hash"] = data["hash"]
		changeCurrentEntry(current)
		changeBranchHash(current["name"], current["hash"])
		puts hash
		puts message
	end

	# replace current files with requested version
	def replace(versionHash)
		hash = getFullHash(versionHash)
		if not hash.nil?
			deleteFiles(@runDir)
			rootInfo = getDataFromJson(File.join(getObjectsDirectory, hash))
			moveFiles(@runDir, rootInfo)
		else
			puts "This version does not exist"
			return
		end
	end

	# prints a list of commits up the chain
	def history
		current = getCurrentEntry
		hash = current["hash"]
		versions = getHistoryEntries
		while not hash.nil?
			versions.each do |version|
				if version["hash"] == hash
					puts "#{version["hash"]}\n#{version["message"]}\n\n"
					hash = version["parent"]
					break
				end
			end
		end
	end

	# create a branch
	def branch(name)
		b = findBranch(name)
		if b.nil?
			current = getCurrentEntry
			newBranch = {"name" => name, "hash" => current["hash"], "parent" => current["hash"]}
			addBranchEntry(newBranch)
		else
			puts "Branch already exists"
		end
	end

	# checkout a branch
	def checkout(branchName)
		checkoutBranch = findBranch(branchName)
		if not checkoutBranch.nil?
			changeCurrentEntry(checkoutBranch)
			replace(checkoutBranch["hash"])
		else
			puts "Branch does not exist"
			return
		end
	end

	# merges a branch into the current branch
	# i'm betting this is going to look like crap
	def merge(branchName)
		source = findBranch(branchName)
		target = getCurrentEntry
		parent = findCommonAncestor(source, target)
		if not source.nil?
			if not parent.nil?
				mergeFilesForDirectory(@runDir, source["hash"], target["hash"], parent["hash"])
				commit("Merged branch #{branchName}")
			else
				puts "Could not find common ancestor"
			end
		else
			puts "Branch doesn't exist"
		end
	end

	# find and display the changes from the current version in the repository
	def status
		current = getCurrentEntry
		changes = findChanges(@runDir, current["hash"])
		if changes.empty?
			puts "No changes made"
		else
			changes.each do |change|
				puts "#{change["name"]} #{change["type"]}"
			end
		end
	end

	# creates a list of changes made
	def findChanges(directory, currentHash)
		currentData = getDataFromJson(File.join(getObjectsDirectory, currentHash))
		changes = []
		# loop through every item in the directory
		Dir.foreach(directory) do |dirItem|
			if dirItem != '.' && dirItem != '..' && dirItem != ".tvc"
				dirPath = File.join(directory, dirItem)
				foundItem = nil
				itemType = File.directory?(dirPath) ? "tree" : "blob"
				# compare the item to the directory's json
				currentData.each_index do |index|
					currentItem = currentData[index]
					if currentItem["name"] == dirItem && currentItem["type"] == itemType
						foundItem = currentItem
						currentData.delete_at(index)
						break
					end
				end
				# if nothing in the json matched this item, it must be new
				if foundItem.nil?
					newChange = { "type" => "added", "name" => dirPath.gsub(@runDir, "") }
					changes << newChange
					if itemType == "tree"
						newChanges = findChangesInNewDirectory(dirPath)
						newChanges.each do |change|
							changes << change
						end
					end
				# we found a match, so we need to compare it
				else
					# if it's a directory, continue down to find changes in there
					if itemType == "tree"
						newChanges = findChanges(dirPath, foundItem["hash"])
						newChanges.each do |newChange|
							changes << newChange
						end
					# if it's a file, compare the contents
					else
						# this is a really hacky way to do this, but i'm so lazy
						repoData = getFileData(File.join(getObjectsDirectory, foundItem["hash"]))
						repoData = repoData.gsub(/\s/, "")
						fileData = File.open(dirPath) { |f| f.read }
						fileData = fileData.gsub(/\s/, "")
						diffs = Diff::LCS.diff(repoData, fileData)
						modified = false
						diffs.each do |diffArray|
							diffArray.each do |diff|
								if diff.action != "=" && diff.element != ""
									modified = true;
								end
							end
						end
						if modified
							newChange = { "type" => "modified", "name" => dirPath.gsub(@runDir, "") }
							changes << newChange
						end
					end
				end
			end
		end
		# if we still have items in the directory json, they must have been deleted
		currentData.each do |currentItem|
			newChange = { "type" => "deleted", "name" => currentItem["name"] }
			changes << newChange
		end
		return changes
	end

	# returns a list of everything in this directory.
	def findChangesInNewDirectory(directory)
		changes = []
		Dir.foreach(directory) do |dirItem|
			if dirItem != '.' && dirItem != '..' && dirItem != ".tvc"
				dirPath = File.join(directory, dirItem)
				newChange = { "type" => "added", "name" => dirPath.gsub(@runDir, "") }
				changes << newChange
				if File.directory?(dirPath)
					newChanges = findChangesInNewDirectory(dirPath)
					newChanges.each do |change|
						changes << change
					end
				end
			end
		end
		return changes
	end

	# attempts to find a common parent for the two revisions
	def findCommonAncestor(source, target)
		sourceParentHash = source["hash"]
		versions = getHistoryEntries
		# loop through until we hit the end of the tree for the source
		while not sourceParentHash.nil?
			sourceParent = nil
			targetParentHash = target["hash"]
			versions.each do |version|
				if version["hash"] == sourceParentHash
					sourceParent = version
					break
				end
			end
			# loop through the target tree, hoping we find something that matches up
			while not targetParentHash.nil?
				versions.each do |version|
					if version["hash"] == targetParentHash
						if targetParentHash == sourceParentHash
							return version
						else
							targetParentHash = version["parent"]
						end
					end
				end
			end
			if sourceParent.nil?
				sourceParentHash = nil
			else
				sourceParentHash = sourceParent["parent"]
			end
		end
		return nil
	end

	# attempts to merge the items for the specified directory together
	def mergeFilesForDirectory(directory, sourceHash, targetHash, parentHash)
		sourceJson = getDataFromJson(File.join(getObjectsDirectory, sourceHash))
		targetJson = getDataFromJson(File.join(getObjectsDirectory, targetHash))
		parentJson = getDataFromJson(File.join(getObjectsDirectory, parentHash))
		# for each item in the source, attempt to find a corresponding item in the target
		sourceJson.each do |sourceItem|
			matchingItem = nil
			parentMatch = nil
			targetJson.each do |targetItem|
				if targetItem["name"] == sourceItem["name"] && targetItem["type"] == sourceItem["type"]
					matchingItem = targetItem
					break
				end
			end
			parentJson.each do |parentItem|
				if parentItem["name"] == sourceItem["name"] && parentItem["type"] == sourceItem["type"]
					parentMatch = parentItem
					break
				end
			end
			# we're only going to attempt to merge if we've found some common parent
			# otherwise, we're just going to straight up replace that thing
			if parentMatch.nil?
				puts "No common ancestor found, pushing change to target"
				createItem(directory, sourceItem)
			# if there's no matching item, but there is a parent, well, i guess it got deleted 
			# in the target, but is needed by source.  add it back in.
			elsif matchingItem.nil?
				puts "No matching item found, pushing change to target"
				createItem(directory, sourceItem)
			# if we've got everything we need, we'll attempt to merge
			else
				# if this is a tree, continue on to do all the logic for it
				if sourceItem["type"] == "tree"
					mergeFilesForDirectory(File.join(directory, sourceItem["name"]), sourceItem["hash"], matchingItem["hash"], parentMatch["hash"])
				# if it's a fine, try to merge the two together
				# man, this might fail horribly with binary files.
				# watch out for that
				elsif sourceItem["type"] == "blob"
					if sourceItem["hash"] != matchingItem["hash"]
						mergeFiles(sourceItem["hash"], matchingItem["hash"], parentMatch["hash"], File.join(directory, sourceItem["name"]))
					end
				end
			end
		end
	end

	# attempt to merge two files together given a common parent
	# this seems like a pretty naive way of doing things, but i'm lazy!
	def mergeFiles(sourceHash, targetHash, parentHash, targetPath)
		sourceData = getFileData(File.join(getObjectsDirectory, sourceHash))
		targetData = getFileData(File.join(getObjectsDirectory, targetHash))
		parentData = getFileData(File.join(getObjectsDirectory, parentHash))
		# get the changes it took to get from the parent to the source
		sourceDiffs = Diff::LCS.diff(parentData, sourceData)
		targetDiffs = Diff::LCS.diff(parentData, targetData)
		# need to modify the source diffs based on the changes between the parent
		# and the target.
		# (this is really hacky and inefficient.  i need to come up with a better 
		# way to do this)
		targetDiffs.each do |targetDiffArray|
			targetDiffArray.each do |targetDiff|
				sourceDiffs.each do |sourceDiffArray|
					sourceDiffArray.each do |sourceDiff|
						if targetDiff.position <= sourceDiff.position
							if targetDiff.action == "-"
								sourceDiff.position -= targetDiff.element.length
							elsif targetDiff.action == "+"
								sourceDiff.position += targetDiff.element.length
							end
						end
					end
				end
			end
		end
		# once we have all the changes between the source and parent, and they've
		# been adjusted by the changes between target and parent, apply the source
		# changes to the target
		mergedData = Diff::LCS.patch!(targetData, sourceDiffs)
		mergedFile = File.open(targetPath, "w")
		mergedFile.write mergedData
		mergedFile.close
	end

	# attempt to create the item specified in the entry
	def createItem(directory, entry)
		# each "tree" item specifies a directory that should be made corresponding to 
		# that directory's json file (hash)
		if entry["type"] == "tree"
			d = directory + '/' + entry["name"]
			Dir.mkdir(d)
			dirJson = getDataFromJson(File.join(getObjectsDirectory, entry["hash"]))
			moveFiles(d, dirJson)
		# copy the item out of the objects folder into its proper place
		elsif entry["type"] == "blob"
			f = File.open(File.join(directory, entry["name"]), "w")
			f.write(getFileData(File.join(getObjectsDirectory, entry["hash"])))
			f.close
		end
	end

	# prints a list of valid functions and their uses
	def help
		puts "help - This text"
		puts "init - Initialize a repository"
		puts "commit - Commit changes to a repository"
		puts "branch - Create a new branch.  If not given a branch name, it lists all current branches."
		puts "checkout - Move to the specified branch for modifying"
		puts "replace - Pulls the desired revision down from the repository"
		puts "merge - Merges the specified branch with the current branch"
		puts "status - Prints a list of changes from the current version of the repository"
	end

	# extracts json data from a given file
	def getDataFromJson(filePath)
		JSON.parse(getFileData(filePath))
	end

	# gets and decompresses a given file
	def getFileData(filePath)
		decompress(File.open(filePath, "rb") { |f| f.read })	
	end

	# decompresses given data
	def decompress(data)
		Zlib::Inflate.inflate(data)
	end

	# compresses and saves data to a path
	def saveFileData(filePath, data)
		f = File.open(filePath, "wb")
		f.write(compress(data))
		f.close
	end

	# compresses given data
	def compress(data)
		Zlib::Deflate.deflate(data)
	end

	# puts data in json format in a given file
	# warning:  this will replace all text in the file
	def saveDataToJson(filePath, data)
		saveFileData(filePath, JSON.generate(data))
	end

	# changes the hash for a specified branch, and sets the parent to the previous hash
	def changeBranchHash(name, hash)
		b = findBranch(name)
		branches = getBranches
		branches.each do |branch|
			if branch == b
				branch["parent"] = branch["hash"]
				branch["hash"] = hash
				saveBranches(branches)
				return
			end
		end
	end

	# returns the path to the objects directory
	def getObjectsDirectory
		return @repoDir + '/' + "objects"
	end

	# adds an entry to the history file
	def addHistoryEntry(entry)
		versions = getHistoryEntries
		versions << entry
		saveDataToJson(File.join(@repoDir, "history"), versions)
	end

	# retrieves the history entries
	def getHistoryEntries
		history = getDataFromJson(File.join(@repoDir, "history"))
	end

	# change the entry in the current file
	def changeCurrentEntry(entry)
		newEntry = [entry]
		saveDataToJson(File.join(@repoDir, "current"), newEntry)
	end

	# get the entry in the current file
	def getCurrentEntry
		current = (getDataFromJson(File.join(@repoDir, "current")))[0]
	end

	# get all branches
	def getBranches
		branches = getDataFromJson(File.join(@repoDir, "pointers"))
	end

	# find a branch.  nil if it does not exist
	def findBranch(name)
		branches = getBranches
		branches.each do |branch|
			if branch["name"] == name
				return branch
			end
		end
		return nil
	end

	# gets a full hash if only given a short hash.
	# allows for easier specification of revisions,
	# but can be kind of dangerous if the short hash is too short
	def getFullHash(hash)
		Dir.foreach(getObjectsDirectory) do |dir|
			dirpath = getObjectsDirectory + '/' + dir
			unless File.directory?(dirpath)
				if dir[0, hash.length] == hash
					return dir
				end
			end
		end
		return nil
	end

	# recursively deletes all files in the directory.
	def deleteFiles(directoryName)
		Dir.foreach(directoryName) do |dir|
			dirpath = directoryName + '/' + dir
			if File.directory?(dirpath)
				if dir != '.' && dir != '..' && dir != ".tvc"
					deleteFiles(dirpath)
					Dir.delete(dirpath)
				end
			else
				File.delete(dirpath)
			end
		end
	end

	# gets files from the given json 
	def moveFiles(directoryName, jsonInfo)
		jsonInfo.each do |item|
			createItem(directoryName, item)
		end
	end

	# save objects in the objects folder, based on hash
	# create json files to index them
	def createObjects(directoryName)
		objects = []
		Dir.foreach(directoryName) do |dir|
			dirpath = directoryName + '/' + dir
			# go down into each valid directory and make objects for its contents
			if File.directory?(dirpath)
				if dir != '.' && dir != '..' && dir != ".tvc"
					hash = createObjects(dirpath)
					data = { "type" => "tree", "name" => dir, "hash" => hash }
					objects << data
				end
			# create a hash based on the file contents
			else
				fileData = File.open(dirpath, "rb") { |f| f.read }
				tempFileName = File.join(@repoDir, "temp")
				saveFileData(tempFileName, fileData)
				hash = createHash(tempFileName)
				data = { "type" => "blob", "name" => dir, "hash" => hash }
				FileUtils.cp(tempFileName, File.join(getObjectsDirectory, hash))
				File.delete(tempFileName)
				objects << data
			end
		end
		# save off objects json file to a temp file
		tempFileName = File.join(@repoDir, "temp")
		saveDataToJson(tempFileName, objects)
		# get the hash for the temp file, save it as that, and return the hash
		hash = createHash(tempFileName)
		FileUtils.cp(tempFileName, File.join(getObjectsDirectory, hash))
		File.delete(tempFileName)
		return hash
	end

	# create a sha2 hash of a file
	def createHash(filePath)
		hashfunc = Digest::SHA2.new
		open(filePath, "rb") do |io|
			while !io.eof
				readBuffer = io.readpartial(1024)
				hashfunc.update(readBuffer)
			end
		end
		return hashfunc.hexdigest
	end

	# add an entry to the branch list
	def addBranchEntry(entry)
		branches = getBranches
		branches << entry
		saveBranches(branches)
	end

	# save off all branches
	def saveBranches(branches)
		saveDataToJson(File.join(@repoDir, "pointers"), branches)
	end

	# get the repository directory
	def getRepositoryDirectory
		while true
			atRoot = true
			Dir.foreach(Dir.getwd) do |dir|
				if dir == ".tvc"
					@runDir = Dir.getwd
					Dir.chdir(".tvc")
					return Dir.getwd
				end
				if dir == ".."
					atRoot = false
				end
			end
			if atRoot
				Dir.chdir(@runDir)
				return nil
			else
				Dir.chdir("..")
			end
		end
	end

	# list all existing branches
	def listBranches
		branches = getBranches
		branches.each do |branch|
			puts branch["name"]
		end
	end

	# main function
	def initialize(args)
		# get directories for use later
		@runDir= Dir.getwd
		@repoDir = getRepositoryDirectory

		# if we're not initializing and we have no repository
		# issue an error and exit
		if args[0] != "init" && @repoDir.nil?
			repositoryIssueError
			Process.exit
		end
		# switch based on command
		case args[0]
		when "init"
			if @repoDir.nil?
				init
			else
				puts "Repository already initialized"
			end
		when "commit"
			commit args[1]
		when "replace"
			replace args[1]
		when "rollback"
			replace args[1]
			commit "Rolled back to #{args[1]}"
		when "reset"
			replace(getCurrentEntry["hash"])
		when "history"
			history
		when "branch"
			if not args[1].nil?
				branch args[1]
			else
				listBranches
			end
		when "checkout"
			checkout args[1]
		when "merge"
			merge args[1]
		when "status"
			status
		else
			help
		end
	end
end
