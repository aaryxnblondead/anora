import React, { useEffect, useState } from 'react';
import { useRouter } from 'expo-router';
import { View, ActivityIndicator, Text } from 'react-native';
import { getOnboardingStatus } from '../state/onboarding';

export default function SplashScreen() {
  const router = useRouter();
  const [message, setMessage] = useState('Preparing your space...');

  useEffect(() => {
    const init = async () => {
      setMessage('Checking your onboarding...');
      const status = await getOnboardingStatus();
      if (status.complete) {
        router.replace('/(tabs)/journal');
        return;
      }
      router.replace('/(auth)/welcome');
    };
    init();
  }, [router]);

  return (
    <View style={{ flex: 1, justifyContent: 'center', alignItems: 'center', gap: 12 }}>
      <ActivityIndicator size="large" />
      <Text style={{ color: '#334155' }}>{message}</Text>
    </View>
  );
}
