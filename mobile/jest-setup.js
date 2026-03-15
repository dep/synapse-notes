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

// Mock expo-file-system
jest.mock('expo-file-system', () => ({
  documentDirectory: 'file:///data/user/0/com.synapse/files/',
  EncodingType: {
    UTF8: 'utf8',
    Base64: 'base64',
  },
  readAsStringAsync: jest.fn(),
  writeAsStringAsync: jest.fn(),
  readDirectoryAsync: jest.fn(),
  getInfoAsync: jest.fn(),
  makeDirectoryAsync: jest.fn(),
  deleteAsync: jest.fn(),
  copyAsync: jest.fn(),
  moveAsync: jest.fn(),
}));

// Mock expo-file-system/legacy
jest.mock('expo-file-system/legacy', () => ({
  documentDirectory: 'file:///data/user/0/com.synapse/files/',
  EncodingType: {
    UTF8: 'utf8',
    Base64: 'base64',
  },
  readAsStringAsync: jest.fn(),
  writeAsStringAsync: jest.fn(),
  readDirectoryAsync: jest.fn(),
  getInfoAsync: jest.fn(),
  makeDirectoryAsync: jest.fn(),
  deleteAsync: jest.fn(),
  copyAsync: jest.fn(),
  moveAsync: jest.fn(),
}));

// Mock react-native
jest.mock('react-native', () => {
  const React = require('react');
  
  const mockComponent = (name) => {
    return React.forwardRef((props, ref) => {
      return React.createElement(name, { ...props, ref });
    });
  };
  
  return {
    View: mockComponent('View'),
    Text: mockComponent('Text'),
    TouchableOpacity: mockComponent('TouchableOpacity'),
    ScrollView: mockComponent('ScrollView'),
    Modal: mockComponent('Modal'),
    TextInput: mockComponent('TextInput'),
    ActivityIndicator: mockComponent('ActivityIndicator'),
    Animated: {
      View: mockComponent('Animated.View'),
      Value: jest.fn((val) => ({
        setValue: jest.fn(),
        _value: val,
      })),
      timing: jest.fn(() => ({
        start: jest.fn((cb) => cb && cb()),
      })),
    },
    StyleSheet: {
      create: jest.fn((styles) => styles),
      flatten: jest.fn((style) => style),
      compose: jest.fn((style1, style2) => [style1, style2]),
      absoluteFill: {
        position: 'absolute',
        left: 0,
        right: 0,
        top: 0,
        bottom: 0,
      },
      hairlineWidth: 1,
    },
    Dimensions: {
      get: jest.fn(() => ({ width: 375, height: 812, scale: 2, fontScale: 1 })),
      addEventListener: jest.fn(() => ({ remove: jest.fn() })),
    },
    useColorScheme: jest.fn(() => 'light'),
    PixelRatio: {
      get: jest.fn(() => 2),
      roundToNearestPixel: jest.fn((value) => value),
    },
    StatusBar: {
      currentHeight: 44,
    },
  };
});

// Mock @expo/vector-icons
jest.mock('@expo/vector-icons', () => {
  const React = require('react');
  return {
    MaterialIcons: React.forwardRef(({ name, ...props }, ref) => {
      return React.createElement('Icon', { ref, name, ...props });
    }),
  };
});

// Mock react-native-safe-area-context
jest.mock('react-native-safe-area-context', () => ({
  SafeAreaView: ({ children, ...props }) => {
    const React = require('react');
    return React.createElement('View', props, children);
  },
  SafeAreaProvider: ({ children }) => {
    const React = require('react');
    return React.createElement('View', null, children);
  },
  useSafeAreaInsets: () => ({ top: 44, bottom: 34, left: 0, right: 0 }),
}));

// Mock useColorScheme from the proper path
jest.mock('react-native/Libraries/Utilities/useColorScheme', () => ({
  default: jest.fn(() => 'light'),
}));
