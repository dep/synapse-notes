import React from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity } from 'react-native';
import { useTheme } from '../theme/ThemeContext';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { RootStackParamList } from '../navigation/AppNavigator';

type SettingsScreenProps = NativeStackScreenProps<RootStackParamList, 'Settings'>;

export function SettingsScreen({ navigation }: SettingsScreenProps) {
  const { theme, isDark, toggleTheme, followSystem, setFollowSystem } = useTheme();

  return (
    <ScrollView
      style={[styles.container, { backgroundColor: theme.colors.background }]}
      contentContainerStyle={styles.content}
    >
      <Text style={[styles.title, { color: theme.colors.text }]}>
        Settings
      </Text>

      <View style={styles.section}>
        <Text style={[styles.sectionTitle, { color: theme.colors.text }]}>
          Appearance
        </Text>
        
        <View style={[styles.card, { backgroundColor: theme.colors.card }]}>
          <View style={styles.settingRow}>
            <Text style={[styles.settingLabel, { color: theme.colors.text }]}>
              Follow System
            </Text>
            <TouchableOpacity
              style={[
                styles.toggle,
                { backgroundColor: followSystem ? theme.colors.primary : theme.colors.border }
              ]}
              onPress={() => setFollowSystem(!followSystem)}
            >
              <Text style={[styles.toggleText, { color: theme.colors.background }]}>
                {followSystem ? 'ON' : 'OFF'}
              </Text>
            </TouchableOpacity>
          </View>

          <View style={styles.divider} />

          <View style={styles.settingRow}>
            <Text style={[styles.settingLabel, { color: theme.colors.text }]}>
              Dark Mode
            </Text>
            <Text style={[styles.settingValue, { color: theme.colors.primary }]}>
              {isDark ? 'Enabled' : 'Disabled'}
            </Text>
          </View>
        </View>
      </View>

      <View style={styles.section}>
        <Text style={[styles.sectionTitle, { color: theme.colors.text }]}>
          About
        </Text>
        
        <View style={[styles.card, { backgroundColor: theme.colors.card }]}>
          <Text style={[styles.infoText, { color: theme.colors.text }]}>
            Synapse Mobile
          </Text>
          <Text style={[styles.infoSubtext, { color: theme.colors.text, opacity: 0.6 }]}>
            Version 1.0.0
          </Text>
        </View>
      </View>

      <TouchableOpacity
        style={[styles.backButton, { backgroundColor: theme.colors.primary }]}
        onPress={() => navigation.goBack()}
      >
        <Text style={[styles.backButtonText, { color: theme.colors.background }]}>
          Go Back
        </Text>
      </TouchableOpacity>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  content: {
    padding: 20,
  },
  title: {
    fontSize: 28,
    fontWeight: 'bold',
    marginBottom: 24,
  },
  section: {
    marginBottom: 24,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 12,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
    opacity: 0.7,
  },
  card: {
    padding: 16,
    borderRadius: 12,
  },
  settingRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  settingLabel: {
    fontSize: 16,
  },
  settingValue: {
    fontSize: 16,
    fontWeight: '600',
  },
  toggle: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 16,
    minWidth: 50,
    alignItems: 'center',
  },
  toggleText: {
    fontSize: 12,
    fontWeight: '600',
  },
  divider: {
    height: 1,
    marginVertical: 12,
    opacity: 0.2,
  },
  infoText: {
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 4,
  },
  infoSubtext: {
    fontSize: 14,
  },
  backButton: {
    paddingHorizontal: 20,
    paddingVertical: 12,
    borderRadius: 8,
    alignItems: 'center',
    marginTop: 16,
  },
  backButtonText: {
    fontSize: 16,
    fontWeight: '600',
  },
});
