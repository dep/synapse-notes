// Define __DEV__ for React Native
global.__DEV__ = true;

// Define __fbBatchedBridgeConfig for React Native
global.__fbBatchedBridgeConfig = {
  remoteModuleConfig: [],
  localModulesConfig: [],
};

// Mock AsyncStorage
jest.mock('@react-native-async-storage/async-storage', () => ({
  setItem: jest.fn(() => Promise.resolve()),
  getItem: jest.fn(() => Promise.resolve(null)),
  removeItem: jest.fn(() => Promise.resolve()),
}));

// Mock TurboModuleRegistry
jest.mock('react-native/Libraries/TurboModule/TurboModuleRegistry', () => ({
  getEnforcing: jest.fn(() => ({})),
  get: jest.fn(() => ({})),
}));

// Mock Dimensions
jest.mock('react-native/Libraries/Utilities/Dimensions', () => ({
  get: jest.fn(() => ({ width: 375, height: 812, scale: 2, fontScale: 1 })),
  addEventListener: jest.fn(() => ({ remove: jest.fn() })),
}));

// Mock PixelRatio
jest.mock('react-native/Libraries/Utilities/PixelRatio', () => ({
  get: jest.fn(() => 2),
  roundToNearestPixel: jest.fn((value) => value),
}));

// Mock NativeDeviceInfo
jest.mock('react-native/Libraries/Utilities/NativeDeviceInfo', () => ({
  __esModule: true,
  default: {
    Dimensions: { window: { width: 375, height: 812, scale: 2, fontScale: 1 } },
  },
}));

// Mock DeviceInfo
jest.mock('react-native/src/private/specs_DEPRECATED/modules/NativeDeviceInfo', () => ({
  __esModule: true,
  default: {
    getConstants: jest.fn(() => ({})),
  },
}));
