
import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import DataLoader
from torch.optim import AdamW
from transformers import (
    AutoModelForSequenceClassification,
    AutoTokenizer,
    get_linear_schedule_with_warmup,
)
from datasets import load_dataset
import logging

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration
TEACHER_MODEL_ID = "mental/mental-bert-base-uncased"
# Using a 6-layer TinyBERT as the student
STUDENT_MODEL_ID = "huawei-noah/TinyBERT_General_6L_768D" 
# Dataset: Using 'dair-ai/emotion' as a proxy for mental health sentiment 
# since a specific 'mental_health_sentiment' dataset isn't standard on HF.
DATASET_ID = "dair-ai/emotion" 
BATCH_SIZE = 16 # Reduce if OOM
EPOCHS = 3
LEARNING_RATE = 2e-5
TEMPERATURE = 2.0
ALPHA = 0.5  # Weight for soft targets vs hard targets
MAX_LENGTH = 128
DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")

def get_data():
    logger.info(f"Loading dataset: {DATASET_ID}")
    try:
        # Load the dataset directly
        dataset = load_dataset(DATASET_ID)
    except Exception as e:
        logger.error(f"Failed to load dataset {DATASET_ID}: {e}")
        raise e
    
    return dataset

def tokenize_data(dataset, tokenizer):
    def tokenize_function(examples):
        return tokenizer(examples['text'], padding="max_length", truncation=True, max_length=MAX_LENGTH)
    
    encoded_dataset = dataset.map(tokenize_function, batched=True)
    # Rename 'label' to 'labels' so the model automatically computes loss
    encoded_dataset = encoded_dataset.rename_column("label", "labels")
    encoded_dataset.set_format(type='torch', columns=['input_ids', 'attention_mask', 'labels'])
    return encoded_dataset

def train_teacher(model, train_loader, val_loader):
    """
    Standard fine-tuning for the teacher model.
    The teacher MUST be fine-tuned on the task before it can teach the student.
    """
    logger.info("Starting Teacher Fine-Tuning...")
    optimizer = AdamW(model.parameters(), lr=LEARNING_RATE)
    model.train()

    # Simple 1-epoch loop for demonstration stability
    for epoch in range(1): 
        total_loss = 0
        for batch in train_loader:
            batch = {k: v.to(DEVICE) for k, v in batch.items()}
            outputs = model(**batch)
            loss = outputs.loss
            loss.backward()
            optimizer.step()
            optimizer.zero_grad()
            total_loss += loss.item()
        logger.info(f"Teacher Epoch {epoch+1} Loss: {total_loss / len(train_loader)}")

    # Save Teacher (optional)
    # model.save_pretrained("./fine_tuned_teacher")
    return model

def distillation_loss_fn(student_logits, teacher_logits, labels, temperature, alpha):
    """
    Knowledge Distillation Loss:
    L = alpha * L_soft + (1 - alpha) * L_hard
    """
    # Soft Loss (KL Divergence)
    soft_targets = F.softmax(teacher_logits / temperature, dim=-1)
    student_log_softmax = F.log_softmax(student_logits / temperature, dim=-1)
    
    # KLDivLoss expects log_probs as input and probs as target
    # reduction='batchmean' aligns with mathematical definition
    soft_loss = F.kl_div(student_log_softmax, soft_targets, reduction='batchmean') * (temperature ** 2)

    # Hard Loss (Cross Entropy)
    hard_loss = F.cross_entropy(student_logits, labels)

    return alpha * soft_loss + (1 - alpha) * hard_loss

def train_student_kd(student_model, teacher_model, train_loader, val_loader):
    """
    Train the student model using Knowledge Distillation.
    """
    logger.info("Starting Student Knowledge Distillation...")
    optimizer = AdamW(student_model.parameters(), lr=LEARNING_RATE)
    
    student_model.train()
    teacher_model.eval() # Teacher must be in eval mode
    
    for epoch in range(EPOCHS):
        total_loss = 0
        for batch in train_loader:
            batch = {k: v.to(DEVICE) for k, v in batch.items()}
            
            with torch.no_grad():
                # Get Teacher Logits
                teacher_outputs = teacher_model(**batch)
                teacher_logits = teacher_outputs.logits
            
            # Get Student Logits
            student_outputs = student_model(**batch)
            student_logits = student_outputs.logits
            
            # Calculate KD Loss
            loss = distillation_loss_fn(
                student_logits, 
                teacher_logits, 
                batch['labels'], 
                TEMPERATURE, 
                ALPHA
            )
            
            loss.backward()
            optimizer.step()
            optimizer.zero_grad()
            
            total_loss += loss.item()
            
        avg_loss = total_loss / len(train_loader)
        logger.info(f"Student Epoch {epoch+1} KD Loss: {avg_loss}")

    logger.info("Distillation Complete.")
    return student_model

def main():
    # 1. Prepare Data
    raw_dataset = get_data()
    num_labels = len(raw_dataset['train'].features['label'].names)
    logger.info(f"Detected {num_labels} labels")
    
    # Use teacher's tokenizer (MentalBERT)
    # Note: You may need to accept the license for 'mental/mental-bert-base-uncased' on Hugging FaceHub
    try:
        tokenizer = AutoTokenizer.from_pretrained(TEACHER_MODEL_ID)
    except Exception as e:
        logger.error("Could not load MentalBERT. Ensure you have access/login via `huggingface-cli login`.")
        raise e

    tokenized_datasets = tokenize_data(raw_dataset, tokenizer)
    
    train_dataset = tokenized_datasets['train']
    val_dataset = tokenized_datasets['validation'] if 'validation' in tokenized_datasets else tokenized_datasets['test']

    train_loader = DataLoader(train_dataset, batch_size=BATCH_SIZE, shuffle=True)
    val_loader = DataLoader(val_dataset, batch_size=BATCH_SIZE)

    # 2. Prepare Teacher
    logger.info("Initializing Teacher...")
    teacher_model = AutoModelForSequenceClassification.from_pretrained(
        TEACHER_MODEL_ID, 
        num_labels=num_labels
    ).to(DEVICE)
    
    # Fine-tune the teacher first! An untrained teacher teaches nothing.
    teacher_model = train_teacher(teacher_model, train_loader, val_loader)

    # 3. Prepare Student
    logger.info("Initializing Student...")
    student_model = AutoModelForSequenceClassification.from_pretrained(
        STUDENT_MODEL_ID, 
        num_labels=num_labels
    ).to(DEVICE)

    # 4. Perform Distillation
    student_model = train_student_kd(student_model, teacher_model, train_loader, val_loader)

    # 5. Save Distilled Student
    output_dir = "./distilled_student_mental_health"
    student_model.save_pretrained(output_dir)
    tokenizer.save_pretrained(output_dir)
    logger.info(f"Distilled model saved to {output_dir}")

if __name__ == "__main__":
    main()
