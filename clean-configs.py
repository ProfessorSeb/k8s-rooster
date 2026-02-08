#!/usr/bin/env python3

import os
import yaml
import re
from pathlib import Path

def clean_metadata(obj):
    """Remove runtime metadata fields"""
    if 'metadata' in obj:
        metadata = obj['metadata']
        # Remove runtime fields
        for field in ['creationTimestamp', 'generation', 'resourceVersion', 'uid', 'selfLink']:
            metadata.pop(field, None)
        
        # Clean annotations of runtime data
        if 'annotations' in metadata:
            annotations = metadata['annotations']
            # Remove kubectl annotations
            annotations.pop('kubectl.kubernetes.io/last-applied-configuration', None)
            annotations.pop('deployment.kubernetes.io/revision', None)
    
    return obj

def clean_status(obj):
    """Remove status fields"""
    obj.pop('status', None)
    return obj

def clean_secrets_and_tokens(obj):
    """Remove or mask sensitive data"""
    # Remove secrets from service accounts
    if obj.get('kind') == 'ServiceAccount' and 'secrets' in obj:
        obj.pop('secrets', None)
    
    # Clean configmap data of sensitive information
    if obj.get('kind') == 'ConfigMap' and 'data' in obj:
        data = obj['data']
        for key, value in data.items():
            if any(sensitive in key.lower() for sensitive in ['password', 'token', 'secret', 'key', 'license']):
                data[key] = "***REDACTED***"
    
    return obj

def clean_yaml_file(file_path):
    """Clean a YAML file of sensitive data and runtime information"""
    print(f"Cleaning {file_path}")
    
    with open(file_path, 'r') as f:
        try:
            documents = yaml.safe_load_all(f)
            cleaned_docs = []
            
            for doc in documents:
                if doc is None:
                    continue
                    
                # Handle both single objects and lists
                if 'items' in doc:  # This is a List object
                    for item in doc['items']:
                        item = clean_metadata(item)
                        item = clean_status(item)
                        item = clean_secrets_and_tokens(item)
                        cleaned_docs.append(item)
                else:  # This is a single object
                    doc = clean_metadata(doc)
                    doc = clean_status(doc)
                    doc = clean_secrets_and_tokens(doc)
                    cleaned_docs.append(doc)
            
            # Write cleaned YAML back
            with open(file_path, 'w') as outfile:
                for i, doc in enumerate(cleaned_docs):
                    if i > 0:
                        outfile.write('\n---\n')
                    yaml.dump(doc, outfile, default_flow_style=False)
                        
        except yaml.YAMLError as e:
            print(f"Error processing {file_path}: {e}")

def main():
    """Clean all YAML files in configs directory"""
    configs_dir = Path('configs')
    
    for yaml_file in configs_dir.rglob('*.yaml'):
        if yaml_file.stat().st_size > 0:  # Skip empty files
            clean_yaml_file(yaml_file)
    
    print("Configuration cleaning completed!")

if __name__ == '__main__':
    main()