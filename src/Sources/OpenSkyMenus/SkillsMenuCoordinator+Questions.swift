// The perk, legendary, and level-up questions are the engine's own message boxes over
// the menu, not part of the movie. See docs/engine/skills-menu.md#the-two-questions.

import Foundation

extension SkillsMenuCoordinator {
    /// Opens a message box for a question the model just asked.
    func askQuestion() {
        guard let question = model?.question else {
            questionAsked = false
            return
        }
        guard !questionAsked, let world else { return }
        questionAsked = true
        world.askSkillsMenuQuestion(question.question, buttons: question.options) { [weak self] in
            self?.answerQuestion($0)
        }
    }

    /// The box's answer; a yes to the first legendary question asks the second.
    func answerQuestion(_ button: Int) {
        questionAsked = false
        guard var model else { return }
        let action = model.answer(button)
        self.model = model
        if let action {
            perform(action)
        }
        askQuestion()
        syncMovie()
    }
}
