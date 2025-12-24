import Foundation

/// Tracks file access and modification times to ensure safe file operations.
///
/// FileTracker ensures that files are read before being modified, and validates
/// that files haven't been changed externally between read and write operations.
public actor FileTracker {
    // MARK: - Types
    
    /// Information about a tracked file
    private struct FileInfo {
        let path: String
        let mtime: Date?
        let wasRead: Bool
    }
    
    // MARK: - Properties
    
    private var trackedFiles: [String: FileInfo] = [:]
    private let requireReadBeforeWrite: Bool
    
    // MARK: - Initialization
    
    /// Initialize a new file tracker
    /// - Parameter requireReadBeforeWrite: If true, files must be read before they can be written (default: true)
    public init(requireReadBeforeWrite: Bool = true) {
        self.requireReadBeforeWrite = requireReadBeforeWrite
    }
    
    // MARK: - Tracking Operations
    
    /// Record that a file has been read
    /// - Parameter path: Absolute path to the file
    /// - Throws: Error if unable to get file attributes
    public func recordRead(path: String) throws {
        let mtime = try getModificationTime(path: path)
        trackedFiles[path] = FileInfo(path: path, mtime: mtime, wasRead: true)
    }
    
    /// Check if a file can be written, and record the write operation
    /// - Parameters:
    ///   - path: Absolute path to the file
    ///   - allowCreate: Whether to allow creating new files (default: true)
    /// - Throws: FileTrackerError if the file cannot be safely written
    public func recordWrite(path: String, allowCreate: Bool = true) throws {
        // Check if file exists
        let fileExists = FileManager.default.fileExists(atPath: path)
        
        // If file doesn't exist and we're not allowing creation, throw error
        if !fileExists && !allowCreate {
            throw FileTrackerError.fileNotFound(path)
        }
        
        // If file exists and requireReadBeforeWrite is enabled, ensure it was read first
        if fileExists && requireReadBeforeWrite {
            guard let info = trackedFiles[path], info.wasRead else {
                throw FileTrackerError.fileNotRead(path)
            }
            
            // Validate that the file hasn't been modified since we read it
            let currentMtime = try getModificationTime(path: path)
            if let originalMtime = info.mtime, let currentMtime = currentMtime {
                if currentMtime != originalMtime {
                    throw FileTrackerError.fileModifiedExternally(path)
                }
            }
        }
        
        // Record the write (file may have new mtime after write, so we'll update on next read)
        // Mark as not read since we've now modified it
        trackedFiles[path] = FileInfo(path: path, mtime: nil, wasRead: false)
    }
    
    /// Check if a file can be updated (similar to write, but for Update tool)
    /// - Parameter path: Absolute path to the file
    /// - Throws: FileTrackerError if the file cannot be safely updated
    public func recordUpdate(path: String) throws {
        // Updates require that the file exists and was read
        guard FileManager.default.fileExists(atPath: path) else {
            throw FileTrackerError.fileNotFound(path)
        }
        
        guard let info = trackedFiles[path], info.wasRead else {
            throw FileTrackerError.fileNotRead(path)
        }
        
        // Validate that the file hasn't been modified since we read it
        let currentMtime = try getModificationTime(path: path)
        if let originalMtime = info.mtime, let currentMtime = currentMtime {
            if currentMtime != originalMtime {
                throw FileTrackerError.fileModifiedExternally(path)
            }
        }
        
        // Record the update
        trackedFiles[path] = FileInfo(path: path, mtime: nil, wasRead: false)
    }
    
    /// Get information about a tracked file
    /// - Parameter path: Absolute path to the file
    /// - Returns: True if the file has been read and not modified since
    public func wasRead(path: String) -> Bool {
        guard let info = trackedFiles[path] else { return false }
        return info.wasRead
    }
    
    /// Clear tracking information for a specific file
    /// - Parameter path: Absolute path to the file
    public func clearTracking(for path: String) {
        trackedFiles.removeValue(forKey: path)
    }
    
    /// Clear all tracking information
    public func clearAll() {
        trackedFiles.removeAll()
    }
    
    /// Get all tracked file paths
    public var trackedPaths: [String] {
        Array(trackedFiles.keys)
    }
    
    // MARK: - Private Helpers
    
    private func getModificationTime(path: String) throws -> Date? {
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        return attributes[.modificationDate] as? Date
    }
}

// MARK: - Errors

/// Errors that can occur during file tracking
public enum FileTrackerError: Error, LocalizedError {
    case fileNotFound(String)
    case fileNotRead(String)
    case fileModifiedExternally(String)
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .fileNotRead(let path):
            return """
                File must be read before modification: \(path)
                Please use the Read tool to read the file content first.
                """
        case .fileModifiedExternally(let path):
            return """
                File has been modified externally since last read: \(path)
                Please use the Read tool to get the latest content before modifying.
                """
        }
    }
}
