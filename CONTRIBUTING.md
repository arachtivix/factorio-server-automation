# Contributing to Factorio Server Automation

Thank you for your interest in contributing! This document provides guidelines for contributing to this project.

## How to Contribute

### Reporting Bugs

If you find a bug, please open an issue with:
- Clear description of the problem
- Steps to reproduce
- Expected vs actual behavior
- Environment details (AWS region, instance type, etc.)
- Relevant logs or error messages

### Suggesting Features

Feature suggestions are welcome! Please open an issue with:
- Clear description of the feature
- Use case and benefits
- Proposed implementation (if you have ideas)

### Submitting Pull Requests

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Test thoroughly
5. Commit with clear messages (`git commit -m 'Add amazing feature'`)
6. Push to your fork (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## Development Guidelines

### Code Style

**Bash Scripts:**
- Use `set -euo pipefail` at the start
- Include descriptive comments
- Use meaningful variable names
- Follow existing formatting conventions
- Add error handling

**Documentation:**
- Use clear, concise language
- Include examples where helpful
- Keep formatting consistent
- Update README if adding features

### Testing

Before submitting:
- Test scripts with bash syntax check: `bash -n script.sh`
- Validate JSON files: `jq empty file.json`
- Test in a clean AWS environment if possible
- Document any manual testing performed

### Commit Messages

- Use present tense ("Add feature" not "Added feature")
- Be descriptive but concise
- Reference issues when applicable (#123)

Example:
```
Add rollback confirmation prompt

- Adds interactive confirmation before rollback
- Prevents accidental version downgrades
- Fixes #123
```

## Areas for Contribution

### High Priority

- [ ] Terraform modules for infrastructure
- [ ] CloudWatch monitoring integration
- [ ] SNS notifications for alerts
- [ ] Automated testing framework
- [ ] Multi-region support

### Medium Priority

- [ ] Docker-based local testing
- [ ] Cost optimization features
- [ ] Performance monitoring
- [ ] Auto-scaling support
- [ ] Custom mod installation from URLs

### Low Priority

- [ ] Web-based management UI
- [ ] Discord bot integration
- [ ] Statistics dashboard
- [ ] Advanced networking (VPC, NAT)
- [ ] Multiple server support

## Project Structure

```
factorio-server-automation/
├── config/              # Configuration files
│   ├── *.conf.example  # Configuration templates
│   └── *.json         # IAM policies, mod lists
├── scripts/            # Bash automation scripts
│   ├── setup-aws.sh   # AWS resource setup
│   ├── deploy-server.sh    # Server deployment
│   ├── manage-factorio.sh  # Server management
│   └── *.sh          # Helper scripts
├── docs/              # Additional documentation (future)
└── *.md              # Documentation
```

## Code Review Process

1. Automated checks run on PR
2. Maintainer reviews code and tests
3. Feedback provided for changes
4. Once approved, PR is merged

## Questions?

Feel free to:
- Open an issue for questions
- Start a discussion on GitHub
- Reach out to maintainers

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

## Code of Conduct

### Our Pledge

We are committed to making participation in this project a harassment-free experience for everyone.

### Our Standards

**Positive behavior:**
- Using welcoming and inclusive language
- Being respectful of differing viewpoints
- Accepting constructive criticism gracefully
- Focusing on what's best for the community

**Unacceptable behavior:**
- Harassment or discriminatory language
- Trolling or insulting comments
- Public or private harassment
- Publishing others' private information

### Enforcement

Instances of unacceptable behavior may be reported by opening an issue or contacting the maintainers. All complaints will be reviewed and investigated.

## Recognition

Contributors will be recognized in the repository and releases!

Thank you for contributing! 🎉
