// Mock the TurboModule spec so TurboModuleRegistry is never evaluated.
// The mock object must be created inside the factory to avoid hoisting issues.
jest.mock('../NativeAtlantisReactNative', () => ({
  __esModule: true,
  default: {
    start: jest.fn(),
    stop: jest.fn(),
    isRunning: jest.fn(() => Promise.resolve(true)),
  },
}));

import NativeAtlantisReactNative from '../NativeAtlantisReactNative';
import { start, stop, isRunning } from '../index';

// Access the mock functions through the mocked module
const mockNative = NativeAtlantisReactNative as unknown as {
  start: jest.Mock;
  stop: jest.Mock;
  isRunning: jest.Mock;
};

beforeEach(() => {
  jest.clearAllMocks();
});

describe('react-native-atlantis', () => {
  describe('start', () => {
    it('calls native start with null when no hostName provided', () => {
      start();
      expect(mockNative.start).toHaveBeenCalledTimes(1);
      expect(mockNative.start).toHaveBeenCalledWith(null);
    });

    it('calls native start with null when undefined is passed', () => {
      start(undefined);
      expect(mockNative.start).toHaveBeenCalledWith(null);
    });

    it('calls native start with the provided hostName', () => {
      start('MacBook-Pro.local');
      expect(mockNative.start).toHaveBeenCalledTimes(1);
      expect(mockNative.start).toHaveBeenCalledWith('MacBook-Pro.local');
    });

    it('passes empty string as hostName when given', () => {
      start('');
      expect(mockNative.start).toHaveBeenCalledWith('');
    });
  });

  describe('stop', () => {
    it('calls native stop', () => {
      stop();
      expect(mockNative.stop).toHaveBeenCalledTimes(1);
    });
  });

  describe('isRunning', () => {
    it('returns the native module promise result (true)', async () => {
      mockNative.isRunning.mockResolvedValueOnce(true);
      const result = await isRunning();
      expect(result).toBe(true);
      expect(mockNative.isRunning).toHaveBeenCalledTimes(1);
    });

    it('returns the native module promise result (false)', async () => {
      mockNative.isRunning.mockResolvedValueOnce(false);
      const result = await isRunning();
      expect(result).toBe(false);
    });

    it('propagates native module rejection', async () => {
      mockNative.isRunning.mockRejectedValueOnce(new Error('native error'));
      await expect(isRunning()).rejects.toThrow('native error');
    });
  });

  describe('module exports', () => {
    it('exports start function', () => {
      expect(typeof start).toBe('function');
    });

    it('exports stop function', () => {
      expect(typeof stop).toBe('function');
    });

    it('exports isRunning function', () => {
      expect(typeof isRunning).toBe('function');
    });
  });
});
