import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  Modal,
  FlatList,
  TextInput,
  ScrollView,
  Platform,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { MaterialIcons } from '@expo/vector-icons';
import { useTheme } from '../theme/ThemeContext';
import { TemplateStorage, FileNode } from '../services';

interface TemplatePickerProps {
  isVisible: boolean;
  onClose: () => void;
  onSelectTemplate: (templatePath: string | null, noteName: string) => void;
  vaultPath: string;
}

export function TemplatePicker({ isVisible, onClose, onSelectTemplate, vaultPath }: TemplatePickerProps) {
  const { theme } = useTheme();
  const [templates, setTemplates] = useState<FileNode[]>([]);
  const [noteName, setNoteName] = useState('');
  const [isLoading, setIsLoading] = useState(false);

  useEffect(() => {
    if (isVisible) {
      loadTemplates();
      setNoteName('');
    }
  }, [isVisible, vaultPath]);

  const loadTemplates = async () => {
    setIsLoading(true);
    try {
      const availableTemplates = await TemplateStorage.getAvailableTemplates(vaultPath);
      setTemplates(availableTemplates);
    } catch (error) {
      console.error('[TemplatePicker] Failed to load templates:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const handleSelectBlank = () => {
    onSelectTemplate(null, noteName.trim() || 'Untitled');
  };

  const handleSelectTemplate = (templatePath: string) => {
    onSelectTemplate(templatePath, noteName.trim() || 'Untitled');
  };

  const getTemplateDisplayName = (template: FileNode): string => {
    let displayName = template.name;
    if (displayName.toLowerCase().endsWith('.md')) {
      displayName = displayName.slice(0, -3);
    } else if (displayName.toLowerCase().endsWith('.markdown')) {
      displayName = displayName.slice(0, -9);
    }
    return displayName;
  };

  const renderTemplateItem = ({ item }: { item: FileNode }) => (
    <TouchableOpacity
      style={[styles.templateItem, { backgroundColor: theme.colors.card }]}
      onPress={() => handleSelectTemplate(item.path)}
    >
      <MaterialIcons
        name="description"
        size={20}
        color={theme.colors.primary}
        style={styles.templateIcon}
      />
      <View style={styles.templateInfo}>
        <Text style={[styles.templateName, { color: theme.colors.text }]}>
          {getTemplateDisplayName(item)}
        </Text>
        <Text style={[styles.templatePath, { color: theme.colors.text + '60' }]} numberOfLines={1}>
          {item.path.replace(vaultPath, '').replace(/^\/+/, '')}
        </Text>
      </View>
    </TouchableOpacity>
  );

  return (
    <Modal
      visible={isVisible}
      transparent={false}
      animationType="slide"
      onRequestClose={onClose}
      presentationStyle="pageSheet"
    >
      <SafeAreaView
        style={[styles.container, { backgroundColor: theme.colors.background }]}
        edges={['top', 'left', 'right', 'bottom']}
      >
        {/* Header */}
        <View style={[styles.header, { borderBottomColor: theme.colors.border }]}>
          <TouchableOpacity onPress={onClose} style={styles.cancelButton}>
            <Text style={[styles.cancelText, { color: theme.colors.primary }]}>Cancel</Text>
          </TouchableOpacity>
          <Text style={[styles.headerTitle, { color: theme.colors.text }]}>
            New Note
          </Text>
          <View style={styles.headerSpacer} />
        </View>

        {/* Scrollable content — scrolls up when keyboard appears */}
        <ScrollView
          style={styles.scrollView}
          contentContainerStyle={styles.scrollContent}
          keyboardShouldPersistTaps="handled"
          keyboardDismissMode="interactive"
          automaticallyAdjustKeyboardInsets={true}
        >
          {/* Note name input */}
          <View style={styles.section}>
            <Text style={[styles.label, { color: theme.colors.text + '80' }]}>
              Note Name
            </Text>
            <TextInput
              style={[
                styles.nameInput,
                {
                  backgroundColor: theme.colors.card,
                  color: theme.colors.text,
                  borderColor: theme.colors.border,
                },
              ]}
              value={noteName}
              onChangeText={setNoteName}
              placeholder="Untitled"
              placeholderTextColor={theme.colors.text + '40'}
              autoFocus={true}
              returnKeyType="done"
              onSubmitEditing={handleSelectBlank}
            />
          </View>

          {/* Blank note option */}
          <View style={styles.section}>
            <Text style={[styles.label, { color: theme.colors.text + '80' }]}>
              Start With
            </Text>
            <TouchableOpacity
              style={[styles.optionRow, { backgroundColor: theme.colors.card }]}
              onPress={handleSelectBlank}
            >
              <View style={[styles.optionIcon, { backgroundColor: theme.colors.primary + '18' }]}>
                <MaterialIcons name="note-add" size={20} color={theme.colors.primary} />
              </View>
              <Text style={[styles.optionText, { color: theme.colors.text }]}>
                Blank Note
              </Text>
              <MaterialIcons name="chevron-right" size={20} color={theme.colors.text + '40'} />
            </TouchableOpacity>

            {templates.map(item => (
              <TouchableOpacity
                key={item.path}
                style={[styles.optionRow, { backgroundColor: theme.colors.card, marginTop: 8 }]}
                onPress={() => handleSelectTemplate(item.path)}
              >
                <View style={[styles.optionIcon, { backgroundColor: theme.colors.primary + '18' }]}>
                  <MaterialIcons name="description" size={20} color={theme.colors.primary} />
                </View>
                <View style={styles.optionTextContainer}>
                  <Text style={[styles.optionText, { color: theme.colors.text }]}>
                    {getTemplateDisplayName(item)}
                  </Text>
                  <Text style={[styles.optionSubtext, { color: theme.colors.text + '50' }]} numberOfLines={1}>
                    {item.path.replace(vaultPath, '').replace(/^\/+/, '')}
                  </Text>
                </View>
                <MaterialIcons name="chevron-right" size={20} color={theme.colors.text + '40'} />
              </TouchableOpacity>
            ))}

            {templates.length === 0 && !isLoading && (
              <Text style={[styles.hint, { color: theme.colors.text + '50' }]}>
                Add .md files to your templates folder to use them here.
              </Text>
            )}
          </View>
        </ScrollView>
      </SafeAreaView>
    </Modal>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 14,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  cancelButton: {
    paddingVertical: 4,
    paddingRight: 12,
    minWidth: 70,
  },
  cancelText: {
    fontSize: 16,
  },
  headerTitle: {
    flex: 1,
    fontSize: 17,
    fontWeight: '600',
    textAlign: 'center',
  },
  headerSpacer: {
    minWidth: 70,
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    padding: 20,
    paddingBottom: 40,
  },
  section: {
    marginBottom: 28,
  },
  label: {
    fontSize: 12,
    fontWeight: '600',
    textTransform: 'uppercase',
    letterSpacing: 0.6,
    marginBottom: 10,
  },
  nameInput: {
    height: 52,
    borderRadius: 12,
    paddingHorizontal: 16,
    fontSize: 17,
    borderWidth: 1,
  },
  optionRow: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 14,
    borderRadius: 12,
  },
  optionIcon: {
    width: 36,
    height: 36,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 12,
  },
  optionTextContainer: {
    flex: 1,
  },
  optionText: {
    fontSize: 16,
    fontWeight: '500',
  },
  optionSubtext: {
    fontSize: 12,
    marginTop: 1,
  },
  templateIcon: {
    marginRight: 12,
  },
  templateInfo: {
    flex: 1,
  },
  templateName: {
    fontSize: 15,
    fontWeight: '500',
    marginBottom: 2,
  },
  templatePath: {
    fontSize: 12,
  },
  hint: {
    fontSize: 13,
    marginTop: 12,
    lineHeight: 18,
  },
});
