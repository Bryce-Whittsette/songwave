// Paste this function into the authorized computer-use session and pass the
// fresh full getAXState() string from the running production-view fixture.
// XCTest maps native headings to staticText on macOS, so this separate check
// protects the AXHeading trait that its public snapshot API cannot distinguish.
function checkSongWaveNativeTree(tree, screen) {
    const headings = screen === 'confirmation'
        ? ['support.heading', 'setup.test.heading', 'setup.confirm.heading']
        : ['support.heading', ...['Trackpad', 'Audio capture', 'Selected app', 'Listening state'].map(s => 'recovery.heading.' + s)];
    for (const id of headings) {
        if (!tree.split('\n').some(line => line.includes('heading Description:') && line.endsWith('ID: ' + id))) {
            throw new Error('Missing native heading role: ' + id);
        }
    }
    const ids = screen === 'confirmation'
        ? ['setup.test', 'setup.confirm', 'setup.recover', 'setup.help', 'support.done']
        : ['recovery.trackpad.retry', 'recovery.trackpad.settings', 'recovery.capture.retry', 'recovery.capture.settings',
           'recovery.app.retry', 'recovery.app.settings', 'recovery.pause.retry', 'recovery.pause.settings', 'recovery.check', 'recovery.copy', 'support.done'];
    const actual = tree.split('\n').flatMap(line => {
        const match = line.match(/button Description: .+?, ID: (.+)$/);
        return match && ids.includes(match[1]) ? [match[1]] : [];
    });
    if (JSON.stringify(actual) !== JSON.stringify(ids)) throw new Error('Unexpected native action order: ' + actual.join(', '));
    if (screen === 'confirmation' && !tree.split('\n').some(line => line.includes('progress indicator Description: Visual music activity') && line.includes('percent') && line.endsWith('ID: music.activity'))) {
        throw new Error('Missing native progress role or useful level description');
    }
    return { screen, headings: headings.length, orderedActions: ids.length, passed: true };
}
