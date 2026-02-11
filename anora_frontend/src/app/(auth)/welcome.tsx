import { useRouter } from 'expo-router';
import { Text, View, StyleSheet } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import Button  from '../../components/ui/Button';

export default function WelcomeScreen() {
  const router = useRouter();

  return (
    <LinearGradient colors={['#F7F8FB', '#E0E7FF']} style={styles.container}>
      <View style={styles.content}>
        <Text style={styles.logo}>Anora.</Text>
        <Text style={styles.tagline}>Your private space for feelings.</Text>
        <View style={styles.spacer} />
        <Button 
          title="Get Started" 
          onPress={() => router.push('/(auth)/privacy')} 
        />
      </View>
    </LinearGradient>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  content: { 
    flex: 1, 
    justifyContent: 'center', 
    alignItems: 'center', 
    padding: 32 
  },
  logo: {
    fontSize: 42,
    fontWeight: '700',
    color: '#5C6AC4', // Primary Indigo
    marginBottom: 8,
  },
  tagline: {
    fontSize: 18,
    color: '#64748B',
    textAlign: 'center',
  },
  spacer: { flex: 0.6 },
});
