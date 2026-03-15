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
    background: '#F9FAFB',
    text: '#111827',
    primary: '#2563EB',
    secondary: '#8B5CF6',
    border: '#E5E7EB',
    card: '#FFFFFF',
    error: '#EF4444',
    success: '#10B981',
  },
};

export const darkTheme: Theme = {
  dark: true,
  colors: {
    background: '#0F172A',
    text: '#F8FAFC',
    primary: '#3B82F6',
    secondary: '#A78BFA',
    border: '#1E293B',
    card: '#1E293B',
    error: '#F87171',
    success: '#34D399',
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
