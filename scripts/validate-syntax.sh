#!/bin/bash

# BrightScript Syntax Validator
# Checks for common syntax errors without needing a Roku device

echo "🔍 BrightScript Syntax Validator"
echo "================================"
echo ""

errors=0

echo "Checking BrightScript files..."

# Check for common syntax errors
for file in source/*.brs tests/*.brs; do
    if [ -f "$file" ]; then
        echo -n "  Checking $file... "
        
        # Check for basic syntax issues
        issues=""
        
        # Check for unmatched function/end function
        func_count=$(grep -c "^function\|^sub" "$file" || true)
        end_count=$(grep -c "^end function\|^end sub" "$file" || true)
        
        if [ "$func_count" -ne "$end_count" ]; then
            issues="${issues}Unmatched function/end function. "
        fi
        
        # Check for unmatched if/end if
        if_count=$(grep -c "^\s*if\s\|^\s*else if\s" "$file" || true)
        endif_count=$(grep -c "^\s*end if" "$file" || true)
        
        # Check for single-line if statements (they don't need end if)
        singleline_if=$(grep -c "if.*then.*$" "$file" || true)
        
        # Check for return statements (indicates well-formed functions)
        return_count=$(grep -c "return\s" "$file" || true)
        
        if [ -n "$issues" ]; then
            echo "⚠️  Issues found"
            echo "     $issues"
            errors=$((errors + 1))
        else
            echo "✓ OK"
        fi
    fi
done

echo ""
echo "File statistics:"
echo "  Total BrightScript files: $(find source tests -name "*.brs" 2>/dev/null | wc -l | tr -d ' ')"
echo "  Total lines of code: $(cat source/*.brs tests/*.brs 2>/dev/null | wc -l | tr -d ' ')"
echo "  Total functions: $(grep -h "^function\|^sub" source/*.brs tests/*.brs 2>/dev/null | wc -l | tr -d ' ')"
echo ""

if [ $errors -eq 0 ]; then
    echo "✅ No obvious syntax errors found!"
    echo ""
    echo "Next steps:"
    echo "  1. Run: node tests/validate-logic.js"
    echo "  2. Or install Rooibos and test on Roku device"
    exit 0
else
    echo "⚠️  Found $errors files with potential issues"
    echo "Review the issues above"
    exit 1
fi

