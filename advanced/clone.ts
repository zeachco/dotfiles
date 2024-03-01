import { $ } from "bun";

const args = process.argv.slice(2);

let repo = 'zeachco';

// if only one argument, setl's assument current user's repo
if (args.length === 2) [repo] = args.splice(0, 1);

const [project] = args;

console.log(`Cloning ${repo}/${project}...`);
await $`git clone git@github.com:${repo}/${project}.git && cd ${project}`;

