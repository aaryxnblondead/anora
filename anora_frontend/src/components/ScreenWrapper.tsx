import React from 'react';
import { SafeAreaView, StyleSheet, ViewProps } from 'react-native';

export default function ScreenWrapper({ children, style, ...props }: ViewProps) {
  return (
    <SafeAreaView style={[styles.wrapper, style]} {...props}>
      {children}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  wrapper: {
    flex: 1,
    backgroundColor: '#F8FAFC',
    paddingHorizontal: 20,
    paddingTop: 8,
  },
});
