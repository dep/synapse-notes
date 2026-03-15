import React, { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import { useColorScheme } from 'react-native';

export interface ThemeColors {
  background: string;
  text: string;
  primary: string;
  secondary: string;
  border: string;
  card: string;
  error: string;
  success: string;
}

export interface Theme {
  dark: boolean;
  colors: ThemeColors;
}

export const lightTheme: Theme = {
  dark: false,
  colors: {
    background: '#FFFFFF',
    text: '#000000',
    primary: '#007AFF',
    secondary: '#5856D6',
    border: '#E5E5E5',
    card: '#F2F2F7',
    error: '#FF3B30',
    success: '#34C759',
  },
};

export const darkTheme: Theme = {
  dark: true,
  colors: {
    background: '#000000',
    text: '#FFFFFF',
    primary: '#0A84FF',
    secondary: '#5E5CE6',
    border: '#38383A',
    card: '#1C1C1E',
    error: '#FF453A',
    success: '#32D74B',
  },
};

interface ThemeContextType {
  theme: Theme;
  isDark: boolean;
  toggleTheme: () => void;
  setTheme: (dark: boolean) => void;
  followSystem: boolean;
  setFollowSystem: (follow: boolean) => void;
}

const ThemeContext = createContext<ThemeContextType | undefined>(undefined);

interface ThemeProviderProps {
  children: ReactNode;
}

export function ThemeProvider({ children }: ThemeProviderProps) {
  const systemColorScheme = useColorScheme();
  const [followSystem, setFollowSystem] = useState(true);
  const [isDark, setIsDark] = useState(systemColorScheme === 'dark');

  useEffect(() => {
    if (followSystem) {
      setIsDark(systemColorScheme === 'dark');
    }
  }, [systemColorScheme, followSystem]);

  const toggleTheme = () => {
    setIsDark(!isDark);
    setFollowSystem(false);
  };

  const setTheme = (dark: boolean) => {
    setIsDark(dark);
    setFollowSystem(false);
  };

  const theme = isDark ? darkTheme : lightTheme;

  return (
    <ThemeContext.Provider
      value={{
        theme,
        isDark,
        toggleTheme,
        setTheme,
        followSystem,
        setFollowSystem,
      }}
    >
      {children}
    </ThemeContext.Provider>
  );
}

export function useTheme(): ThemeContextType {
  const context = useContext(ThemeContext);
  if (context === undefined) {
    throw new Error('useTheme must be used within a ThemeProvider');
  }
  return context;
}
